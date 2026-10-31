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
# CANCEL_FIGHTER_SELECTION: the player backed out of an activation before any
# attacks were assigned. The controller tears down the attack dialog / melee
# visuals on this; the picker is re-emitted separately.
signal fighter_selection_cancelled(unit_id: String)
# Codex: Space Marines (11e) WIND-SWIFT EVASION (SMCodex11e.gd): the end-of-phase
# normal / fall-back move, driven by the same reactive-move panel (and the same
# signal names / ORK11E_REACTIVE_MOVE_* actions) as the Shooting phase's moves.
signal ork11e_reactive_move_started(info: Dictionary)
signal ork11e_reactive_move_updated(info: Dictionary)
signal ork11e_reactive_move_ended(info: Dictionary)
var sm11e_fight_move: Dictionary = {}  # the move in progress (SMCodexAMovement.fight_move_*)

static func _sm11e_movement():
	return load("res://scripts/codex/space_marines/SMCodexAMovement.gd")

## The WIND-SWIFT EVASION move in progress, for the move panel and scenarios.
func ork11e_reactive_move_info(positions: Dictionary = {}) -> Dictionary:
	return _sm11e_movement().fight_move_info(self, positions)

## A human's WIND-SWIFT EVASION move keeps the AI idle (AIPlayer reads this).
func get_pending_stratagem_window_decider() -> int:
	var decider := super.get_pending_stratagem_window_decider()
	if decider == 0 and not sm11e_fight_move.is_empty():
		return int(sm11e_fight_move.get("player", 0))
	return decider

# Fight state tracking
var active_fighter_id: String = ""
var selected_weapon_id: String = ""  # Currently selected weapon for active fighter
var pending_attacks: Array = []
var confirmed_attacks: Array = []
# WP-S4 (SWAbilities11e) Hammer Blow: the finished activation's assignments, read by the unit_has_fought window.
var _sw11e_fought_assignments: Array = []
var _sw11e_dice_mark: int = 0
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

# Codex: Orks (11e) FIGHT group hooks (design .llm/ork_codex_11e_design.md
# §3, §3.2, §6.2): enemy_targets_unit_fight / fight_phase_end windows, the
# embark / strategic_reserves follow-ups and the shared 05.04.05 Fight On
# Death mechanic of ORKS IS NEVER BEATEN / TOO ARROGANT TO DIE / CRAZED RAMPAGE.
const OrkCodexFight = preload("res://scripts/stratagems/ork_codex/OrkCodexFight.gd")
# Codex: Orks (11e) detachment rules (WP-O34): 'Ard as Nails, Try Dat Button!, Visions of Violence.
const Ork11eDetachments = preload("res://scripts/codex/orks/OrkDetachments11e.gd")
var _ork11e_selected_to_fight: Dictionary = {}   # unit_id -> true once selected to fight this phase
var _ork11e_fod_rolled: Dictionary = {}          # "unit_id:model_index" -> true (D6 rolled, or a removal)
var _ork11e_fod_destroyer: Dictionary = {}       # unit_id -> enemy fighter whose attacks destroyed its kept models (event attribution)
var _window_deferred_batch: Dictionary = {}      # {window_id, player, actions}: BATCH sub-actions held while a window waits
var _fight_phase_end_window_opened: bool = false # the fight_phase_end window opens once per phase
var _fight_phase_start_window_opened: bool = false # the fight_phase_start window opens once per phase (WP-C3)
var _kill_reported_units: Dictionary = {}        # unit_id -> true once _check_kill_diffs processed its destruction

func _init():
	phase_type = GameStateData.Phase.FIGHT

func _on_phase_enter() -> void:
	log_phase_message("Entering Fight Phase")
	_cus11e_step_asked.clear()
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
	consolidation_step_11e = ConsolidationStep11e.NOT_STARTED
	consolidating_player_11e = 0
	consolidation_done_players_11e.clear()
	units_that_consolidated_11e.clear()
	pile_in_step_11e = PileInStep11e.NOT_STARTED
	piling_in_player_11e = 0
	pile_in_done_players_11e.clear()
	overrun_pile_in_unit_11e = ""
	_pending_pile_in_step_data = {}
	_ork11e_selected_to_fight.clear()
	_ork11e_fod_rolled.clear()
	_ork11e_fod_destroyer.clear()
	_window_deferred_batch = {}
	_fight_phase_end_window_opened = false
	_fight_phase_start_window_opened = false
	_kill_reported_units.clear()
	# Clear stale eligibility stamps from a previous fight phase (e.g. a
	# loaded save) before this phase re-stamps them.
	_clear_fight_eligibility_stamps_11e()

	# (Codex: Adeptus Custodes (11e) Moment Shackle is a "start of any phase"
	# ability card in the phase_start window — CustodesAbilities.gd, WP-C7.)

	# Apply unit ability effects (leader abilities, always-on abilities)
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_phase_start(GameStateData.Phase.FIGHT)
	# WP-M4c FEARSOME ASSAULT (Reiver Squad): start of the Fight phase — each enemy unit engaged with Reivers makes a battle-shock roll at -1.
	load("res://scripts/codex/space_marines/SMAbilitiesC.gd").on_fight_phase_start()

	# Refresh snapshot after ability effects mutated GameState flags
	game_state_snapshot = GameState.create_snapshot()

	# Codex: Orks (11e) Wurrband — Visions of Violence "at the start of the Fight
	# phase" (WP-O34): decided before the FightSequencer / Pile In step begin.
	var ork11e_fs: Array = Ork11eDetachments.fight_start_window_entries(GameState.get_active_player())
	if not ork11e_fs.is_empty() and open_stratagem_windows(ork11e_fs, "_ork11e_resume_after_fight_start", {}):
		log_phase_message("Waiting for the start-of-Fight-phase psychic ability decision (Visions of Violence)")
		return
	_initialize_fight_sequence()
	_check_for_combats()

## Codex: Orks (11e) start-of-Fight-phase window answered (WP-O34): build the
## fight sequence (Fights First now includes Visions of Violence) and begin.
func _ork11e_resume_after_fight_start(_ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	game_state_snapshot = GameState.create_snapshot()
	_initialize_fight_sequence()
	_check_for_combats()
	return create_result(true, [])

func _on_phase_exit() -> void:
	log_phase_message("Exiting Fight Phase")

	# Codex: Orks (11e) Fight On Death: a model kept on the battlefield is
	# removed at the end of the phase at the latest. Normally done by
	# _run_end_of_fight_triggers; this covers a phase left any other way.
	var fod_exit_diffs = _ork11e_fod_remove_all("the end of the Fight phase")
	if not fod_exit_diffs.is_empty():
		PhaseManager.apply_state_changes(fod_exit_diffs)
		_check_kill_diffs(fod_exit_diffs)
	Ork11eDetachments.on_phase_end("fight")  # Codex: Orks (11e) Try Dat Button! / Visions of Violence / 'Ard as Nails flags (WP-O34)

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

	# 11e 12.01 start of the Fight phase (the fight_phase_start windows), then
	# 12.02: the fight phase OPENS with the global Pile In step — both
	# players pile in their eligible units (active player first) before any
	# unit is selected to fight.
	_start_fight_phase_after_start_rules()

## 12.01 "Rules that are triggered at the start of the Fight phase are
## resolved now": the fight_phase_start stratagem window (WP-C3 — the Codex:
## Adeptus Custodes DACATARAI / KAPTARIS ka'tahs, CustodesKatah.gd, and the
## stratagems that use it), active player first, then the non-active player,
## once per phase; the Pile In step begins when it closes. Returns the phase
## result (window diffs + the Pile In step's triggers).
func _start_fight_phase_after_start_rules() -> Dictionary:
	if not _fight_phase_start_window_opened:
		_fight_phase_start_window_opened = true
		var fps_ctx := {"phase": "fight"}
		if _is_network_client():
			# The HOST opens the window; when a human there has something to
			# decide, the Pile In step starts from the host's answer (its result
			# carries trigger_pile_in_selection) — not locally, beside the window.
			var active := get_current_player()
			for p in [active, 2 if active == 1 else 1]:
				if not _is_ai_window_decider(p) and not _window_offers_for(p, "fight_phase_start", fps_ctx).is_empty():
					log_phase_message("[11e 12.01] network client: P%d has fight_phase_start offers — the Pile In step follows the host's decision" % p)
					return create_result(true, [])
		if open_stratagem_window_both_players("fight_phase_start", fps_ctx, "_resume_after_fight_phase_start_window"):
			log_phase_message("[11e 12.01] start of the Fight phase — waiting for Player %d's fight_phase_start decision" % get_pending_stratagem_window_decider())
			return create_result(true, consume_window_diffs())
	var start_diffs := consume_window_diffs()
	var res := _begin_pile_in_step_11e()
	if not start_diffs.is_empty():
		start_diffs.append_array(res.get("changes", []))
		res["changes"] = start_diffs
	return res

## Resume point for the fight_phase_start windows (BasePhase framework).
func _resume_after_fight_phase_start_window(_ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	log_phase_message("[11e 12.01] fight_phase_start windows answered — the Pile In step begins")
	return _begin_pile_in_step_11e()


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
		# Units destroyed / battle-shocked by Deadly Demise or emergency
		# disembarks above open their stratagem windows too (design §3).
		if _ev_depth == 0:
			_window_events_flush(result)

	return result

## Stratagem-window attribution (enemy_unit_has_attacked): the active fighter.
func _window_attacking_unit_id() -> String:
	return active_fighter_id

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
				# A unit's destruction is processed ONCE per phase: the same
				# alive=false diffs can reach this hook twice (applied early by
				# a flow, then again from the action result — e.g. the Fight On
				# Death removal at the end of the phase), and a second pass would
				# double-count the kill and re-roll Deadly Demise.
				if all_dead and _kill_reported_units.has(unit_id):
					continue
				if all_dead:
					_kill_reported_units[unit_id] = true
					# Credit the destroyed unit's OPPONENT: in the Fight phase both
					# players destroy units, so the active player is not
					# necessarily the one who destroyed it.
					var _kd_owner = int(unit.get("owner", 0))
					var destroyed_by = (2 if _kd_owner == 1 else 1) if _kd_owner in [1, 2] else get_current_player()
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
					# (Codex: Adeptus Custodes Superior Creation rolls at the end of the
					# phase — PhaseManager -> CustodesEnhancements.gd, WP-C46.)
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
			var unplaceable = int(unit_info.get("models_unplaceable", 0))
			if mw > 0:
				var _mw_label = "mortal wound" if mw == 1 else "mortal wounds"
				var _md_label = "model" if destroyed_models == 1 else "models"
				log_phase_message("  %s: %d %s, %d %s destroyed" % [unit_name, mw, _mw_label, destroyed_models, _md_label])
			elif unplaceable == 0:
				log_phase_message("  %s: disembarked safely" % unit_name)
			if unplaceable > 0:
				# 18.05: "Each model that cannot be set up in this way is destroyed."
				log_phase_message("  %s: %d model(s) could not be set up wholly within 6\" of the transport and were destroyed (18.05)" % [unit_name, unplaceable])

		# Recursively check if transport destruction casualties caused further deaths
		_check_kill_diffs(result.all_diffs)

## Deadly Demise is resolved by this phase's own kill detection
## (_check_kill_diffs), not by the BasePhase generic event path.
func _phase_resolves_deadly_demise() -> bool:
	return true

func _resolve_deadly_demise_if_applicable(destroyed_unit_id: String) -> void:
	"""P1-13: Check if a destroyed unit has Deadly Demise and resolve it."""
	# Stratagem window unit_destroyed opens BEFORE Deadly Demise (design §3,
	# FLYIN' HEADBUTT): hold the roll until that window closes.
	if _window_hold_deadly_demise(destroyed_unit_id):
		return
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
		# Codex: Orks (11e) Fight On Death: models these mortal wounds destroy
		# roll to stay on the battlefield like any other destroyed model.
		_ork11e_fod_intercept(diffs)
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

	# Codex: Space Marines (11e) WIND-SWIFT EVASION move (SMCodex11e.gd): its own
	# actions, and nothing else while it is in progress.
	var sm11e_gate: Dictionary = _sm11e_movement().fight_move_gate(self, action)
	if not sm11e_gate.is_empty():
		return sm11e_gate

	match action_type:
		"SELECT_FIGHTER":
			return _validate_select_fighter(action)
		"CANCEL_FIGHTER_SELECTION":
			return _validate_cancel_fighter_selection(action)
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
		"END_FIGHT":
			return _validate_end_fight(action)
		"END_CONSOLIDATION":
			return _validate_end_consolidation(action)
		"END_PILE_IN":
			return _validate_end_pile_in(action)
		# Codex: Adeptus Custodes (CustodesCodex11e.gd): a unit chosen in the Pile In /
		# Consolidate step opens unit_selected_to_pile_in / _to_consolidate first.
		"CUS11E_SELECT_PILE_IN_UNIT", "CUS11E_SELECT_CONSOLIDATION_UNIT":
			return _cus11e_validate_step_unit(action)
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
		"USE_STRATAGEM":
			return _validate_use_stratagem(action)
		"END_CHARGE":
			# Idempotent no-op: previous phase auto-advanced before END_CHARGE was dispatched.
			return {"valid": true}
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	var result = _process_fight_action(action)
	# Codex: Orks (11e) Fight On Death: every model destroyed by this action
	# (attacks, hazard rolls, mortal wounds…) of a unit under ORKS IS NEVER
	# BEATEN / TOO ARROGANT TO DIE / CRAZED RAMPAGE rolls its D6 BEFORE the
	# diffs are applied (BasePhase applies result.changes after this returns).
	if typeof(result) == TYPE_DICTIONARY and result.get("success", false) and result.get("changes", null) is Array:
		_ork11e_fod_intercept(result.changes)
	return result

func _process_fight_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	# Codex: Space Marines (11e) WIND-SWIFT EVASION move (SMCodex11e.gd): the reactive-move panel's actions.
	if str(action_type).begins_with("ORK11E_REACTIVE_MOVE_"):
		return _sm11e_movement().fight_move_action(self, action)

	match action_type:
		"SELECT_FIGHTER":
			return _process_select_fighter(action)
		"CANCEL_FIGHTER_SELECTION":
			return _process_cancel_fighter_selection(action)
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
		"END_FIGHT":
			return _process_end_fight(action)
		"END_CONSOLIDATION":
			return _process_end_consolidation(action)
		"END_PILE_IN":
			return _process_end_pile_in(action)
		"CUS11E_SELECT_PILE_IN_UNIT", "CUS11E_SELECT_CONSOLIDATION_UNIT":
			return _cus11e_process_step_unit(action)
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
		# 19.03: an attached CHARACTER has no activation of its own — it fights
		# inside its bodyguard's. Say so rather than the generic "not eligible",
		# which read as a bug when the Warboss was plainly in combat.
		if RulesEngine.is_attached_character(unit_id, GameState.state):
			var host_id = RulesEngine.attached_unit_target_id(unit_id, GameState.state)
			return {"valid": false, "errors": [
				"%s fights as part of %s — select the Attached unit, it swings as one (19.03)" % [
					unit.get("meta", {}).get("name", unit_id),
					_fight_attached_display_name(host_id)]]}
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
	# 19.03: any component of the activated Attached unit may pick a weapon —
	# the leader's is part of the same swing.
	if not _is_in_active_fight_group(unit_id):
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

	# Check the attacker belongs to the activation. 19.03: an Attached unit
	# fights as ONE unit in ONE activation, so an assignment may name the
	# bodyguard OR any attached character — the Warboss's power klaw is part of
	# his Boyz' swing, not a second activation of his own. RulesEngine resolves
	# each assignment against its own `attacker`, so both keep their own stats.
	if not _is_in_active_fight_group(unit_id):
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

	# 19.02: an attached CHARACTER is part of ONE Attached unit and can never
	# be picked as a melee target on its own. _get_eligible_melee_targets
	# already hides these from the UI; this is the authoritative engine gate
	# for callers that bypass it (the AI's fight plan used to select attached
	# leaders directly, and the defender then had no bodyguard models to
	# allocate wounds to — every wound went straight onto the leader).
	if RulesEngine.is_attached_character(target_id, game_state_snapshot):
		var bodyguard_id = RulesEngine.attached_unit_target_id(target_id, game_state_snapshot)
		var attached_name = target_unit.get("meta", {}).get("display_name", target_unit.get("meta", {}).get("name", target_id))
		var bodyguard_name = get_unit(bodyguard_id).get("meta", {}).get("name", bodyguard_id)
		errors.append("Cannot target '%s' — attached character; fight '%s' (the Attached unit) instead" % [attached_name, bodyguard_name])

	# Check units are within engagement range. Measured against the whole
	# Attached unit (19.03) so a target engaged only via its attached leader's
	# model is still reachable.
	#
	# NOTE the asymmetry, and that it is deliberate: the TARGET is the whole
	# Attached unit, the ATTACKER is only the component named by `unit_id`.
	# 11e Fight ("Select Targets") makes each target's legality a property of
	# the MODEL that carries the weapon — "each target must be engaged with the
	# model that has that weapon" — and an Attached unit's components stand in
	# different places, so the bodyguard cannot swing at an enemy that only its
	# leader's model has reached. Callers that build a plan for a whole
	# activation must narrow per component first (melee_targets_for_component).
	if not _units_in_engagement_range(unit, {"models": RulesEngine.attached_unit_models(target_id, game_state_snapshot)}):
		var attacker_label = unit.get("meta", {}).get("name", unit_id)
		var target_label = target_unit.get("meta", {}).get("name", target_id)
		if _fight_group_ids(unit_id).size() > 1 or _fight_is_attached_character(unit_id):
			errors.append("'%s' is not within Engagement Range of '%s' — another part of its Attached unit is, but each model can only attack what IT is engaged with" % [attacker_label, target_label])
		else:
			errors.append("'%s' is not within Engagement Range of '%s'" % [attacker_label, target_label])

	# Check weapon exists and is melee
	var weapon = RulesEngine.get_weapon_profile(weapon_id)
	if weapon.is_empty():
		errors.append("Weapon not found: " + weapon_id)
	elif weapon.get("type", "").to_lower() != "melee":
		errors.append("Weapon is not a melee weapon: " + weapon_id)

	# 11e core rules (Fight — Select Melee Weapon): "you must select one melee
	# weapon that model has" — each model fights with ONE melee weapon per
	# activation; [EXTRA ATTACKS] weapons are used IN ADDITION and are exempt.
	var conflicting_weapon = _find_one_weapon_rule_conflict(weapon_id, action.get("attacking_models", []), unit_id)
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
	var max_reach = consol_dist + GameConstants.engagement_range_inches()  # consolidation distance + engagement range (2" at 11e, 1" at 10e)
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

	# 11e: SKIP_UNIT only ends the ACTIVE fighter's activation — the unit has
	# already been selected to fight (12.04) and e.g. has no target it can
	# attack. It can no longer be used on a unit that has not been selected:
	# every eligible unit must be selected to fight (12.04), so skipping one
	# would forfeit a mandatory fight (core-rules audit e28e4f7, P0-2).
	if sequencer_11e == null:
		return {"valid": false, "errors": ["Fight sequencer not initialized"]}
	if unit_id != "" and unit_id == active_fighter_id:
		return {"valid": true, "errors": []}
	if sequencer_11e.eligible_to_fight(unit_id, GameState.state):
		errors.append("%s must be selected to fight — eligible units cannot be skipped (12.04)" % get_unit(unit_id).get("meta", {}).get("name", unit_id))
	else:
		errors.append("Unit %s has no fight to skip" % unit_id)
	return {"valid": false, "errors": errors}

# Action processing methods
func _process_select_fighter(action: Dictionary) -> Dictionary:
	active_fighter_id = action.unit_id
	# Codex: Orks (11e) Fight On Death gate: "if your unit has not been
	# selected to fight this phase" — the whole Attached unit is now selected.
	for _fod_sel_id in _fight_group_ids(active_fighter_id):
		_ork11e_selected_to_fight[_fod_sel_id] = true

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

	# STRATAGEM WINDOW unit_selected_to_fight (design §3): "when a unit is
	# selected to fight (either player's unit), before attacks" — the FIGHTER'S
	# OWNER decides (HIT 'EM HARDER, MOW 'EM DOWN, UNBRIDLED CARNAGE, ARMED TO
	# DA TEEF …, and the Codex: Adeptus Custodes RENDAX ka'tah of a readied
	# unit — CustodesKatah.gd). Opens before Epic Challenge so the
	# chosen buff is in place for everything that follows the selection.
	var fighter_owner := int(get_unit(active_fighter_id).get("owner", current_selecting_player))
	var stf_ctx := {"phase": "fight", "unit_id": active_fighter_id}
	if open_stratagem_window(fighter_owner, "unit_selected_to_fight", stf_ctx, "_resume_after_selected_to_fight_window"):
		log_phase_message("Waiting for Player %d's unit_selected_to_fight stratagem decision for %s" % [fighter_owner, active_fighter_id])
		return create_result(true, consume_window_diffs())
	var after_window = _after_selected_to_fight_windows(active_fighter_id)
	var stf_sync_diffs = consume_window_diffs()
	if not stf_sync_diffs.is_empty():
		stf_sync_diffs.append_array(after_window.get("changes", []))
		after_window["changes"] = stf_sync_diffs
	return after_window

## Resume point for the unit_selected_to_fight window (BasePhase framework).
func _resume_after_selected_to_fight_window(ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	return _after_selected_to_fight_windows(str(ctx.get("unit_id", active_fighter_id)))

## Everything that follows "selected to fight" once the stratagem window has
## closed: Epic Challenge → fight moves/attacks.
func _after_selected_to_fight_windows(fighter_id: String) -> Dictionary:
	active_fighter_id = fighter_id
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

	# No Epic Challenge available - the fight itself
	return _proceed_to_fight_moves(active_fighter_id)

# ============================================================================
# CANCEL_FIGHTER_SELECTION — back out of an activation before any attack lands
# ============================================================================
#
# The reported soft-lock: picking a unit to fight retires the fighter-selection
# panel and opens the AttackAssignmentDialog. That dialog is an AcceptDialog, so
# Escape / the window ✕ / pad Ⓑ (PadBindingManager points ui_cancel at it) just
# HID it — leaving active_fighter_id set, no picker on screen and no dialog to
# assign with. The phase's only reachable action was END_FIGHT, which throws
# away every remaining swing. Reported from the T6 tutorial ("Krumpin'", step 4)
# by a player who activated the Warboss, realised the lesson wanted the Boyz,
# and pressed Ⓑ — but it strands any fight-phase activation, tutorial or not.
#
# Cancelling means the selection NEVER HAPPENED: the sequencer un-stamps the
# unit and hands the pick back to its owner, so the same unit (or any other
# candidate) can be selected again. Only legal while nothing has been committed
# — no assigned attacks, no rolled dice, no pending saves; once the dice are
# out, SKIP_UNIT / the resolution dock own the activation.
func _validate_cancel_fighter_selection(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", active_fighter_id)
	if active_fighter_id == "":
		return {"valid": false, "errors": ["No fighter is selected"]}
	if unit_id != active_fighter_id:
		return {"valid": false, "errors": ["%s is not the active fighter (%s)" % [unit_id, active_fighter_id]]}
	if not pending_attacks.is_empty() or not confirmed_attacks.is_empty():
		return {"valid": false, "errors": ["Attacks are already assigned — resolve or skip the activation"]}
	if not staged_fight_state.is_empty() or awaiting_melee_saves:
		return {"valid": false, "errors": ["The fight is already being resolved"]}
	if unit_id in units_that_fought:
		return {"valid": false, "errors": ["%s has already fought" % unit_id]}
	return {"valid": true, "errors": []}

func _process_cancel_fighter_selection(action: Dictionary) -> Dictionary:
	var unit_id = str(action.get("unit_id", active_fighter_id))
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	log_phase_message("[11e 12.04] Activation of %s cancelled before any attacks — back to fighter selection" % unit_name)

	# Drop everything the (never-completed) activation staged.
	active_fighter_id = ""
	for _fod_sel_id in _fight_group_ids(unit_id):
		_ork11e_selected_to_fight.erase(_fod_sel_id)  # the selection never happened
	selected_weapon_id = ""
	pending_attacks.clear()
	confirmed_attacks.clear()
	resolution_state = {}
	if overrun_pile_in_unit_11e == unit_id:
		overrun_pile_in_unit_11e = ""

	# Un-commit the sequencer: the unit is eligible again and the pick returns
	# to its owner, so re-selecting it (or a different unit) is the next step.
	if sequencer_11e != null:
		sequencer_11e.unselect_to_fight(unit_id, GameState.state)
		current_selecting_player = int(get_unit(unit_id).get("owner", current_selecting_player))

	emit_signal("fighter_selection_cancelled", unit_id)
	# Put the picker back on screen — without this the cancel would strand the
	# player exactly as the silent dialog-hide did.
	_emit_fight_selection_required()
	return create_result(true, [])

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
		# Spent for the whole phase, not just this activation: an activation the
		# player CANCELS (CANCEL_FIGHTER_SELECTION) and re-makes must not hand
		# out a second 3" overrun move.
		var _op_gs_unit = GameState.get_unit(unit_id)
		if not _op_gs_unit.is_empty():
			if not _op_gs_unit.has("flags"):
				_op_gs_unit["flags"] = {}
			_op_gs_unit["flags"]["overrun_pile_in_made_this_phase"] = true
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
# 19.03: model references are indices/ids WITHIN one component unit, so the
# comparison is per attacker — the Warboss's only model is "0" just as the
# first Boy is, and without this scoping his power klaw collided with their
# choppas and was dropped from the Attached unit's swing.
func _find_one_weapon_rule_conflict(weapon_id: String, attacking_models: Array, attacker_unit_id: String = "") -> String:
	if RulesEngine.has_extra_attacks(weapon_id, game_state_snapshot):
		return ""
	var attacker_id = attacker_unit_id if attacker_unit_id != "" else active_fighter_id
	var new_models = _normalize_model_refs(attacking_models)
	for pending in pending_attacks:
		var pending_weapon = str(pending.get("weapon", ""))
		if pending_weapon == "":
			continue
		if str(pending.get("attacker", active_fighter_id)) != attacker_id:
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
	var conflicting_weapon = _find_one_weapon_rule_conflict(weapon_id, action.get("attacking_models", []), unit_id)
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
	var _perf_t0 := Time.get_ticks_usec()
	# Move pending attacks to confirmed attacks (but don't resolve yet)
	confirmed_attacks = pending_attacks.duplicate(true)
	# WP-S4 Hammer Blow ("hit by those attacks"): this activation's assignments and where its dice start.
	_sw11e_fought_assignments = confirmed_attacks.duplicate(true)
	_sw11e_dice_mark = dice_log.size()
	pending_attacks.clear()

	# T3-3: Auto-inject Extra Attacks weapons if not already assigned
	# This is a safety net for AI/auto-resolve paths that bypass the dialog
	_auto_inject_extra_attacks_weapons()

	# MA-LOADOUT: same safety net for the models the AI's single weapon pick
	# leaves out — see _auto_assign_unassigned_models.
	_auto_assign_unassigned_models()

	var _perf_t1 := Time.get_ticks_usec()
	emit_signal("fighting_begun", active_fighter_id)
	var _perf_t2 := Time.get_ticks_usec()

	# Show mathhammer predictions before rolling
	_show_mathhammer_predictions()
	var _perf_t3 := Time.get_ticks_usec()

	# Only when it actually costs something — this confirm is the action that
	# used to stall for 3.6 s (see _show_mathhammer_predictions), so leave the
	# breakdown in as a tripwire rather than re-deriving it next time.
	var _perf_total_ms := (_perf_t3 - _perf_t0) / 1000.0
	if _perf_total_ms >= 5.0:
		DebugLogger.info("[PERF] FightPhase.CONFIRM_AND_RESOLVE_ATTACKS: inject=%.1fms fighting_begun=%.1fms mathhammer=%.1fms TOTAL=%.1fms" % [
			(_perf_t1 - _perf_t0) / 1000.0,
			(_perf_t2 - _perf_t1) / 1000.0,
			(_perf_t3 - _perf_t2) / 1000.0,
			_perf_total_ms
		])

	log_phase_message("Attack assignments confirmed for %s - ready to roll dice!" % active_fighter_id)

	# STRATAGEM WINDOW enemy_targets_unit_fight (design §3): "after an enemy
	# fighter's targets are known, before any attack is rolled" — the OWNER of
	# the targeted unit(s) decides (ORKS IS NEVER BEATEN, TOO ARROGANT TO DIE,
	# CRAZED RAMPAGE). The dice are rolled by the next action (ROLL_DICE, or the
	# rest of the UI's BATCH_FIGHT_ACTIONS, which the resume replays).
	var etf_targets: Array = _enemy_targets_unit_fight_targets()
	if not etf_targets.is_empty():
		var etf_fighter_owner := int(get_unit(active_fighter_id).get("owner", current_selecting_player))
		var etf_decider := 2 if etf_fighter_owner == 1 else 1
		var etf_ctx := {"phase": "fight", "attacker_unit_id": active_fighter_id, "target_unit_ids": etf_targets}
		if open_stratagem_window(etf_decider, "enemy_targets_unit_fight", etf_ctx, "_resume_after_enemy_targets_fight_window"):
			log_phase_message("Waiting for Player %d's enemy_targets_unit_fight stratagem decision (%s attacks %s)" % [etf_decider, active_fighter_id, str(etf_targets)])
			return create_result(true, consume_window_diffs())
	return create_result(true, consume_window_diffs())

## The units the active fighter's confirmed attacks target, Attached units
## folded to their bodyguard (one entry per unit) — the window's ctx.
func _enemy_targets_unit_fight_targets() -> Array:
	var out: Array = []
	var fighter_owner := int(get_unit(active_fighter_id).get("owner", 0))
	for attack in confirmed_attacks:
		var tid := str(attack.get("target", ""))
		if tid == "" or get_unit(tid).is_empty():
			continue
		var head := str(RulesEngine.attached_unit_target_id(tid, GameState.state))
		if int(get_unit(head).get("owner", 0)) == fighter_owner:
			continue
		if not head in out:
			out.append(head)
	return out

## Resume point for the enemy_targets_unit_fight window: the attacker's
## activation continues — if the UI's batch was held back at CONFIRM, its
## remaining sub-actions (ROLL_DICE) run now; otherwise the attacker sends
## ROLL_DICE next (the AI does so on its own).
func _resume_after_enemy_targets_fight_window(_ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	var deferred: Dictionary = _window_deferred_batch
	_window_deferred_batch = {}
	var actions: Array = deferred.get("actions", [])
	if str(deferred.get("window_id", "")) == "enemy_targets_unit_fight" and not actions.is_empty():
		log_phase_message("enemy_targets_unit_fight answered — resuming the held fight batch (%d sub-action(s))" % actions.size())
		return _process_batch_fight_actions({"type": "BATCH_FIGHT_ACTIONS", "sub_actions": actions,
			"player": int(deferred.get("player", 0))})
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
	# windows) — mirrors ShootingPhase's sequential_staged mode. An AI attacker
	# stages too when the HUMAN is the defender (see _should_stage_fight):
	# the enemy's swing back is rolled out in the same dock instead of landing
	# as a finished "N wounds to save" prompt. Networked games and explicit
	# fast_roll keep the one-shot paths below.
	var interactive_saves = defender_is_human and not _auto_alloc_11e
	if _should_stage_fight(action, interactive_saves):
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

func _should_stage_fight(action: Dictionary, interactive_saves: bool = true) -> bool:
	if action.get("payload", {}).get("fast_roll", false):
		return false
	if NetworkManager.is_networked():
		return false
	if not _fight_attacker_is_ai():
		return true
	# ENEMY SWING BACK: an AI attacker stages ONLY when the human defender is
	# about to roll their own saves anyway (interactive_saves). Reported: the
	# enemy's melee landed as a finished "20 wound(s) to save" prompt with the
	# hit and wound rolls dumped into the log all at once — the player never saw
	# them roll. Staging routes them through the same dock the player's own
	# attacks use (hit pause → wound pause → saves), and the HUMAN advances it.
	#
	# The interactive_saves gate is what makes that safe: it is only true when a
	# real defender UI is present (SettingsService loaded, auto-allocate off,
	# human-owned target). Stripped headless harnesses have no SettingsService,
	# so they keep the one-shot resolution and nothing waits for a click that
	# will never come. AIPlayer._human_defender_window_pending() reports the
	# pause so the AI idles instead of racing the player's dock.
	return interactive_saves

## True when THIS activation's attacks will be resolved through the staged dock
## (hit pause → wound pause → saves) rather than in one shot. FightController
## asks before it activates the resolution dock, so it never puts a dock up that
## would get no pause events. Mirrors _process_roll_dice's own gate, and is safe
## to call from `fighting_begun` (confirmed_attacks is already populated).
func fight_activation_will_stage() -> bool:
	var ss = get_node_or_null("/root/SettingsService")
	# (null service == stripped headless harness -> auto-allocate, same as
	# _process_roll_dice above and ShootingPhase._should_pause_for_human_saves.)
	var auto_alloc: bool = ss == null or ss.get_auto_allocate_wounds()
	if NetworkManager.is_networked():
		auto_alloc = false
	return _should_stage_fight({}, _is_defender_human_player() and not auto_alloc)

# True while the unit currently making attacks belongs to an AI player.
func _fight_attacker_is_ai() -> bool:
	var fighter_owner = get_unit(active_fighter_id).get("owner", get_current_player())
	var ai_player = get_node_or_null("/root/AIPlayer")
	if ai_player == null or not ai_player.get("enabled"):
		return false
	if not ai_player.has_method("is_ai_player"):
		return false
	return ai_player.is_ai_player(fighter_owner)

func _fight_reroll_available() -> bool:
	# A staged hit/wound Command Re-roll is offered when the ATTACKING player has
	# not already used Command Re-roll this phase and can pay the CP.
	# Never on an AI attacker's dice: the human is only stepping the reveal of
	# the enemy's swing back, and those are not their dice to re-roll (their own
	# Command Re-roll comes later, on their saves, in the allocation overlay).
	if _fight_attacker_is_ai():
		return false
	var sm = get_node_or_null("/root/StratagemManager")
	if sm == null or not sm.has_method("is_command_reroll_available"):
		return false
	var fighter_owner = get_unit(active_fighter_id).get("owner", get_current_player())
	var chk = sm.is_command_reroll_available(fighter_owner, active_fighter_id)
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
	# 19.03: an Attached unit's activation carries assignments from more than
	# one component, so name the one actually swinging — "Warboss → … with
	# Power klaw" rather than filing his klaw under his Boyz.
	var swinger_id = str(assignment.get("attacker", active_fighter_id))
	if get_unit(swinger_id).is_empty():
		swinger_id = active_fighter_id
	var fighter_name = get_unit(swinger_id).get("meta", {}).get("name", swinger_id)

	GameEventLog.add_combat_header("P%d: %s → %s with %s (weapon %d/%d)" % [
		get_unit(swinger_id).get("owner", get_current_player()), fighter_name, target_name, weapon_name,
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
		"die_evals": hc.get("hit_evals", []),  # per-die re-roll provenance (Captain-General etc.) for the dock chips
		"hits": hc.get("hits", 0),
		"threshold": str(hc.get("ws", hc.get("bs", 4))) + "+",
		# Named provenance for every hit modifier that applied — the dock lists
		# these so "hitting on 2+" is traceable to the rule that caused it.
		"modifier_ledger": hc.get("modifier_ledger", [])
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
	# interactive_saves: the human defender allocates via the save overlay.
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
		"die_evals": wc.get("wound_evals", []),
		"wounds": wounds,
		"target_name": get_unit(assignments[idx].get("target", "")).get("meta", {}).get("name", ""),
		"threshold": str(wc.get("wound_threshold", 4)) + "+",
		"modifier_ledger": wc.get("modifier_ledger", [])
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

	# Auto-allocate: run the save/damage tail synchronously (exactly like the
	# one-shot monolith path).
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
			# LV2-G1: show the hazard roll in the Game Log (after this weapon's
			# combat card), as the shooting phase does.
			if str(hazard.get("game_log_text", "")) != "":
				GameEventLog.add_player_entry(int(fighter_unit.get("owner", get_current_player())), str(hazard.get("game_log_text", "")))
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
	# Never re-roll a dice more than once — refuse before spending the CP
	# (RulesEngine.reroll_hit_die / reroll_wound_die refuse it too; r5:F7).
	var rr_ctx: Dictionary = staged_fight_state.get("hit_context", {}) if stage == "hits" else staged_fight_state.get("wound_context", {})
	if RulesEngine.staged_die_already_rerolled(rr_ctx, stage, die_index):
		return create_result(false, [], "That die has already been re-rolled — a dice can never be re-rolled more than once")

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
			"die_evals": uhc.get("hit_evals", []),
			"hits": uhc.get("hits", 0),
			"modifier_ledger": uhc.get("modifier_ledger", [])
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
			"die_evals": rr.get("wound_context", {}).get("wound_evals", []),
			"wounds": new_wounds,
			"modifier_ledger": rr.get("wound_context", {}).get("modifier_ledger", [])
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
	_window_deferred_batch = {}

	DebugLogger.info(str("[FightPhase] Processing BATCH_FIGHT_ACTIONS with %d sub-actions" % sub_actions.size()))

	for i in range(sub_actions.size()):
		var sub = sub_actions[i]
		# Copy player/timestamp from parent action if not present
		if not sub.has("player"):
			sub["player"] = action.get("player", 0)
		if not sub.has("timestamp"):
			sub["timestamp"] = action.get("timestamp", 0)

		DebugLogger.info(str("[FightPhase] Batch sub-action %d: %s" % [i, sub.get("type", "")]))

		# Validate HERE, not in _validate_batch_fight_actions. That pre-flight
		# can only check sub-action 0 (everything after it depends on state the
		# earlier ones write), so it deliberately skips the rest — but
		# process_action does NOT validate either, and the gap let an illegal
		# later ASSIGN_ATTACKS resolve in full. Observed: an attached Blade
		# Champion assigned to a mob 8" away swung at it anyway, because the
		# bodyguard's assignment happened to sort first and pass.
		# By the time we get here the earlier sub-actions HAVE been applied, so
		# the state each check sees is the right one.
		var sub_validation = validate_action(sub)
		if not sub_validation.get("valid", false):
			var sub_errors = sub_validation.get("errors", [])
			var sub_error_text: String = ", ".join(sub_errors) if (sub_errors is Array and not sub_errors.is_empty()) else "Action not allowed"
			push_error("[FightPhase] Batch sub-action %d (%s) rejected: %s" % [i, sub.get("type", ""), sub_error_text])
			log_phase_message("Fight batch rejected at step %d (%s): %s" % [i, sub.get("type", ""), sub_error_text])
			return {"success": false, "error": sub_error_text, "errors": sub_errors}

		var result = process_action(sub)

		if not result.get("success", false):
			push_error("[FightPhase] Batch sub-action %d (%s) failed: %s" % [i, sub.get("type", ""), result.get("log_text", "unknown error")])
			return result

		# Accumulate state changes from all sub-actions
		if result.has("changes"):
			all_changes.append_array(result.get("changes", []))

		last_result = result

		# A sub-action opened a stratagem window that waits for a HUMAN
		# decider: the rest of the batch depends on that answer, so stop here
		# (the window's resume continues the activation; the AI re-plans).
		if has_pending_stratagem_window():
			log_phase_message("Fight batch paused after step %d (%s) — stratagem window %s pending for Player %d; %d sub-action(s) dropped" % [
				i, sub.get("type", ""), str(get_pending_stratagem_window().get("window_id", "")),
				get_pending_stratagem_window_decider(), sub_actions.size() - i - 1])
			# enemy_targets_unit_fight opens at CONFIRM: the attacker's dice
			# (ROLL_DICE) are held and replayed by the window's resume, so the
			# human attacker's one-click "Confirm" still rolls once answered.
			var paused_window_id := str(get_pending_stratagem_window().get("window_id", ""))
			if paused_window_id == "enemy_targets_unit_fight" and i + 1 < sub_actions.size():
				_window_deferred_batch = {"window_id": paused_window_id, "player": int(action.get("player", 0)),
					"actions": sub_actions.slice(i + 1)}
				log_phase_message("Fight batch: %d sub-action(s) held until the enemy_targets_unit_fight window is answered" % (sub_actions.size() - i - 1))
			break

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
			# ARMOUR SAVES IN THE GAME LOG: the batch's raw blocks use the
			# engine-internal "save" context, which no log renderer matches —
			# normalize them to "save_roll"/"feel_no_pain" first so melee saves
			# show up on the combat card exactly like the shooting ones.
			for dice_block in RulesEngine.normalize_allocation_11e_dice(save_result_summary, {
				"target_unit_name": target_name,
				"weapon_name": save_data.get("weapon_name", ""),
			}):
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
# 19.03: run for EVERY component of the Attached unit — the Warboss's attack
# squig is [EXTRA ATTACKS] and swings alongside his Boyz' choppas in the one
# activation, so his own unit needs the same injection the bodyguard gets.
func _auto_inject_extra_attacks_weapons() -> void:
	if active_fighter_id.is_empty():
		return
	for member_id in _fight_group_ids(active_fighter_id):
		_auto_inject_extra_attacks_for_unit(member_id)

func _auto_inject_extra_attacks_for_unit(fighter_id: String) -> void:
	var unit = get_unit(fighter_id)
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

	# Check which EA weapons are already assigned — for THIS component (the same
	# weapon name on two components is two different models' attacks).
	var assigned_weapon_ids = {}
	for attack in confirmed_attacks:
		if str(attack.get("attacker", active_fighter_id)) != fighter_id:
			continue
		assigned_weapon_ids[attack.get("weapon", "")] = true

	# Determine default target: this component's own swing first, then the rest
	# of the activation. 19.03 components stand apart, so the bodyguard's target
	# is not necessarily one this component's models have reached — and 11e
	# requires each target to be engaged with the model making the attacks.
	# reachable_melee_target_for clamps to something it IS engaged with.
	var default_target = ""
	for attack in confirmed_attacks:
		if str(attack.get("attacker", active_fighter_id)) == fighter_id and str(attack.get("target", "")) != "":
			default_target = str(attack.get("target", ""))
			break
	if default_target == "" and not confirmed_attacks.is_empty():
		default_target = str(confirmed_attacks[0].get("target", ""))
	if default_target != "":
		var ea_target := reachable_melee_target_for(fighter_id, default_target)
		if ea_target != default_target:
			log_phase_message("[19.03] %s is not engaged with %s — its Extra Attacks swing at %s" % [
				fighter_id, default_target, ea_target if ea_target != "" else "nothing"])
		default_target = ea_target

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
			"attacker": fighter_id,
			"weapon": weapon_id,
			"target": default_target
		})
		DebugLogger.info(str("[FightPhase] T3-3: Auto-injected Extra Attacks weapon '%s' → '%s'" % [weapon_name, default_target]))

	log_phase_message("T3-3: Extra Attacks weapons auto-included for %s" % fighter_id)

# MA-LOADOUT: give the models a whole-unit assignment missed a weapon of their own.
#
# An ASSIGN_ATTACKS with no model list means "the whole unit", and the engine now
# narrows that to the models which actually CARRY the named weapon (a mob told to
# swing a Power klaw no longer swings ten of them). The AI submits exactly one
# such assignment per activation, so on a mixed mob — 9 Boyz with choppas, 1 Boss
# Nob with a big choppa — the odd model out would simply not attack.
#
# 11e Fight — Select Weapons is per model: that Boss Nob picks his own weapon and
# swings alongside them. So every eligible model still left out is assigned the
# one melee weapon it carries, against the target the unit is already fighting.
#
# Only ever fills gaps left by a whole-unit assignment: if ANY pending assignment
# names its models explicitly, a per-model path (the AttackAssignmentDialog) chose
# them and a model left out was left out ON PURPOSE — nothing is added.
# 19.03: runs for EVERY component of the Attached unit. A component with no
# assignment of its own is the case that matters — the AI submits ONE
# whole-unit assignment naming the bodyguard, so without this the attached
# Warboss contributed nothing to the activation he is now part of (and, before
# the Attached unit fought as one, took a second activation of his own to do
# it). See _auto_assign_group_weapon_for_unit.
func _auto_assign_unassigned_models() -> void:
	if active_fighter_id.is_empty():
		return
	for member_id in _fight_group_ids(active_fighter_id):
		_auto_assign_unassigned_models_for_unit(member_id)

func _auto_assign_unassigned_models_for_unit(fighter_id: String) -> void:
	var unit = get_unit(fighter_id)
	if unit.is_empty():
		return

	var regular: Array = []
	for attack in confirmed_attacks:
		if str(attack.get("attacker", active_fighter_id)) != fighter_id:
			continue
		if RulesEngine.has_extra_attacks(str(attack.get("weapon", "")), game_state_snapshot):
			continue  # used IN ADDITION — never consumes a model's weapon choice
		if not attack.get("models", []).is_empty():
			return  # a per-model path drove this activation; respect its choices
		regular.append(attack)

	# The target the Attached unit is already fighting. This component's OWN
	# assignments win when it has any (its gap-filled models join the swing
	# their squadmates are already making); otherwise fall back to the rest of
	# the activation, since an attached component may have no assignment yet.
	var default_target = ""
	for attack in regular:
		if str(attack.get("target", "")) != "":
			default_target = str(attack.get("target", ""))
			break
	if default_target == "":
		for attack in confirmed_attacks:
			if str(attack.get("target", "")) != "":
				default_target = str(attack.get("target", ""))
				break
	if default_target == "":
		return

	# ...but "the target the ACTIVATION is fighting" is not necessarily one THIS
	# component's models have reached (19.03 components stand apart, and 11e
	# requires each target to be engaged with the model swinging at it). Clamp
	# to a target this component is actually in Engagement Range of — inheriting
	# the bodyguard's pick blind wrote assignments that skip validation and
	# would resolve attacks from models nowhere near the unit they hit.
	var component_target := reachable_melee_target_for(fighter_id, default_target)
	if component_target == "":
		log_phase_message("[19.03] %s is in no enemy's Engagement Range — no auto-assigned attacks for it" % fighter_id)
		return
	if component_target != default_target:
		log_phase_message("[19.03] %s is not engaged with %s — its models swing at %s instead" % [
			fighter_id, default_target, component_target])
	default_target = component_target

	if regular.is_empty():
		# Nothing assigned for this component at all. For the unit that was
		# actually selected that means a per-model path drove it (or it has no
		# attacks), and we must not invent any. For an ATTACHED component it
		# means the caller only described the bodyguard's swing — but they are
		# ONE unit fighting ONE activation, so its models still attack.
		if fighter_id == active_fighter_id:
			return
		_auto_assign_group_weapon_for_unit(fighter_id, default_target)
		return

	var eligible = RulesEngine.get_eligible_melee_model_indices(unit, game_state_snapshot)
	if eligible.is_empty():
		return

	# {model index -> [melee weapon name]} for this unit, as actually carried.
	var per_model = RulesEngine.get_unit_melee_weapons(fighter_id, game_state_snapshot)
	var by_index := _melee_weapons_by_model_index(per_model)

	# Which models the existing whole-unit assignments already cover.
	var covered := {}
	for attack in regular:
		var wid = str(attack.get("weapon", ""))
		for idx in by_index:
			for wname in by_index[idx]:
				if RulesEngine.generate_weapon_id(str(wname), "Melee") == wid:
					covered[idx] = true
					break

	# Gap-fill, but only where the model's weapon is unambiguous — a model still
	# reporting a MENU of options is a choice we must not make for the player.
	var extra := {}
	for idx in eligible:
		if covered.has(idx) or not by_index.has(idx):
			continue
		var names = by_index[idx]
		if names.size() != 1:
			continue
		var wid = RulesEngine.generate_weapon_id(str(names[0]), "Melee")
		if RulesEngine.has_extra_attacks(wid, game_state_snapshot):
			continue
		if not extra.has(wid):
			extra[wid] = []
		extra[wid].append(str(idx))

	for wid in extra:
		confirmed_attacks.append({
			"attacker": fighter_id,
			"weapon": wid,
			"target": default_target,
			"models": extra[wid]
		})
		log_phase_message("Auto-assigned %s for %d model(s) the unit's weapon pick left out → %s" % [
			wid, extra[wid].size(), default_target])
		DebugLogger.info(str("[FightPhase] MA-LOADOUT: gap-filled '%s' for models %s of %s → %s" % [
			wid, str(extra[wid]), fighter_id, default_target]))

# 19.03: an attached component nobody assigned anything for — every one of its
# eligible models swings the best melee weapon it carries, at the target the
# rest of the Attached unit is fighting. Unlike the gap-filler above this does
# NOT require the model's weapon to be unambiguous: staying silent would mean
# the Leader simply does not fight, which is the bug this exists to prevent.
# The pick matches AttackAssignmentDialog._best_weapon_for_model, so the AI's
# swing and a hand-driven one land on the same weapon.
func _auto_assign_group_weapon_for_unit(fighter_id: String, target_id: String) -> void:
	var unit = get_unit(fighter_id)
	if unit.is_empty():
		return
	var eligible = RulesEngine.get_eligible_melee_model_indices(unit, game_state_snapshot)
	if eligible.is_empty():
		log_phase_message("[19.03] %s (part of the Attached unit) has no model eligible to fight — no attacks from it" % fighter_id)
		return
	var by_index := _melee_weapons_by_model_index(
		RulesEngine.get_unit_melee_weapons(fighter_id, game_state_snapshot))

	var by_weapon := {}
	for idx in eligible:
		if not by_index.has(idx):
			continue
		var wid = _best_melee_weapon_id(unit, by_index[idx])
		if wid == "":
			continue
		if not by_weapon.has(wid):
			by_weapon[wid] = []
		by_weapon[wid].append(str(idx))

	for wid in by_weapon:
		confirmed_attacks.append({
			"attacker": fighter_id,
			"weapon": wid,
			"target": target_id,
			"models": by_weapon[wid]
		})
		log_phase_message("[19.03] %s fights with the Attached unit: %s for %d model(s) → %s" % [
			get_unit(fighter_id).get("meta", {}).get("name", fighter_id),
			wid, by_weapon[wid].size(), target_id])
		DebugLogger.info(str("[FightPhase] 19.03: attached component '%s' auto-assigned '%s' for models %s → %s" % [
			fighter_id, wid, str(by_weapon[wid]), target_id]))

# get_unit_melee_weapons keys ("m3" or "3") -> int model index.
func _melee_weapons_by_model_index(per_model: Dictionary) -> Dictionary:
	var by_index := {}
	for key in per_model:
		var k = str(key)
		var idx := -1
		if k.begins_with("m") and k.substr(1).is_valid_int():
			idx = k.substr(1).to_int()
		elif k.is_valid_int():
			idx = k.to_int()
		if idx >= 0:
			by_index[idx] = per_model[key]
	return by_index

# The melee weapon a model should swing when nobody chose for it: the highest
# average attacks x damage it carries, strength breaking ties. [EXTRA ATTACKS]
# weapons are skipped — they are used IN ADDITION and are injected separately.
func _best_melee_weapon_id(unit: Dictionary, weapon_names: Array) -> String:
	var best_id := ""
	var best_score := -1.0
	for wname in weapon_names:
		var wid = RulesEngine.generate_weapon_id(str(wname), "Melee")
		if RulesEngine.has_extra_attacks(wid, game_state_snapshot):
			continue
		var profile := {}
		for w in unit.get("meta", {}).get("weapons", []):
			if str(w.get("name", "")) == str(wname):
				profile = w
				break
		var score: float = RulesEngine.average_dice_notation(str(profile.get("attacks", "1"))) \
			* RulesEngine.average_dice_notation(str(profile.get("damage", "1"))) * 100.0 \
			+ RulesEngine.average_dice_notation(str(profile.get("strength", "0")))
		if score > best_score:
			best_score = score
			best_id = wid
	return best_id


func _show_mathhammer_predictions() -> void:
	# Pre-roll "what should I expect" line, shown in the combat log the moment
	# attacks are confirmed.
	#
	# PERF (2026-08-01): this used to call Mathhammer's Monte-Carlo simulator
	# with 1000 trials PER TARGET. Each trial replays the full
	# RulesEngine (~1.9 ms on a 26-unit board), and the whole thing runs
	# synchronously inside the BATCH_FIGHT_ACTIONS that then rolls the dice —
	# so the game froze for the duration. Measured on this exact path:
	# CONFIRM_AND_RESOLVE_ATTACKS = 3605 ms total, of which 3583 ms was this
	# function. That is the "several second hang after confirming weapons"
	# reported from the Steam Deck; splitting attacks across two targets
	# doubled it. Mathhammer.analytic_forecast() computes the same two numbers
	# in closed form in well under a millisecond — see the assumptions
	# documented on it (abilities/FNP/modifiers are not modelled, hence "~").
	if confirmed_attacks.is_empty():
		return

	var _perf_t0 := Time.get_ticks_usec()
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

		# Build the weapon slices for this target. The model list on the
		# assignment is what actually swings — a one-model Power klaw must not
		# be multiplied by the whole mob (MA-LOADOUT).
		var weapon_specs = []
		var weapon_texts = []
		for attack in target_attacks:
			var weapon_id = attack.get("weapon", "")
			var attacking_models = attack.get("models", [])

			var model_count = attacking_models.size()
			if model_count <= 0:
				# Default to all alive models
				model_count = 0
				for i in range(attacker_models.size()):
					if attacker_models[i].get("alive", true):
						model_count += 1

			weapon_specs.append({
				"weapon_id": weapon_id,
				"model_count": model_count
			})

			var w_profile = Mathhammer.resolve_weapon_profile(weapon_id, attacker_unit, game_state_snapshot)
			weapon_texts.append(w_profile.get("name", weapon_id))

		var forecast = Mathhammer.analytic_forecast(weapon_specs, target_unit, game_state_snapshot, true, attacker_unit)
		var avg_damage = forecast.get("expected_damage", 0.0)
		var kill_prob = forecast.get("kill_probability", 0.0) * 100.0

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
	DebugLogger.info(str("[FightPhase] Mathhammer prediction (analytic, %.2fms): %s" % [(Time.get_ticks_usec() - _perf_t0) / 1000.0, prediction_text]))

	# Display predictions via dice_rolled signal (like shooting phase)
	emit_signal("dice_rolled", {
		"context": "mathhammer_prediction",
		"message": prediction_text
	})

func _get_consolidation_distance(unit_id: String) -> float:
	"""OA-26: Returns the consolidation distance for a unit.
	Normally 3\", but 6\" for units with 'Drive-by Krumpin'' ability, and the
	numeric effect_consolidate_max flag (ALWAYS LOOKIN' FER A FIGHT)
	overrides with its own cap when larger."""
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
	var flag_max = float(unit.get("flags", {}).get("effect_consolidate_max", 0.0))
	if flag_max > dist:
		log_phase_message("Consolidation distance %.0f\" for %s (effect_consolidate_max)" % [flag_max, unit_id])
		dist = flag_max
	# Codex: Adeptus Custodes (11e) Unstoppable Destroyer / Dacatarai (WP-C46).
	if GameConstants.edition >= 11:
		dist = float(_cus11e_det().fight_move_cap(unit_id, dist))
	return dist

# 11e: a unit's activation ends when its attacks are resolved — there is
# NO per-fighter consolidation (that is the global 12.07 step at the end
# of the phase). This performs the activation-completion bookkeeping that
# _process_consolidate performs at edition 10 (has_fought,
# Counter-Offensive window, next-fighter handoff), then either offers the
# next fight selection or — when the Fight step is over — waits for
# END_FIGHT, or resumes the Consolidate step if a 12.08 forced fight just
# finished. Augments and returns the caller's final_result so the
# trigger_* metadata rides the same result NetworkManager broadcasts.
func _finish_fight_activation_11e(final_result: Dictionary) -> Dictionary:
	var unit_id = active_fighter_id
	var changes: Array = final_result.get("changes", [])

	# Codex: Orks (11e) Fight On Death (05.04.05) — BEFORE the early apply
	# below decides the next fighter from the post-attack board: (1) models of
	# a unit under ORKS IS NEVER BEATEN / TOO ARROGANT TO DIE / CRAZED RAMPAGE
	# destroyed by this activation roll to stay on the battlefield; (2) this
	# unit has now fought, so the models IT kept that way are removed.
	_ork11e_fod_intercept(changes)
	changes.append_array(_ork11e_fod_remove(_fight_group_ids(unit_id), "has fought"))
	changes.append_array(Ork11eDetachments.on_unit_has_fought(unit_id))  # Codex: Orks (11e) Try Dat Button! hazard roll + expiry (WP-O34)
	final_result["changes"] = changes

	# The attack-resolution diffs are normally applied by execute_action
	# AFTER process returns — but the next-selection / Counter-Offensive /
	# Consolidate-step decisions below must see the post-attack board
	# (casualties change eligibility). Apply them now; execute_action's
	# re-apply is idempotent (set ops), same pattern as Dread Foe.
	if not changes.is_empty():
		PhaseManager.apply_state_changes(changes)

	# 19.03: the whole Attached unit has now had its one fight — stamp every
	# component. Marking only the bodyguard left the Leader unfought, so he was
	# offered a second activation and the enemy got to swing in between.
	var group_ids = _fight_group_ids(unit_id)
	for member_id in group_ids:
		changes.append({
			"op": "set",
			"path": "units.%s.flags.has_fought" % member_id,
			"value": true
		})
		if not member_id in units_that_fought:
			units_that_fought.append(member_id)
	if sequencer_11e != null:
		for member_id in group_ids:
			sequencer_11e.mark_fought(member_id)
	changes.append_array(_fight_done_changes_11e(unit_id))
	final_result["changes"] = changes
	active_fighter_id = ""
	confirmed_attacks.clear()

	# The 12.06 overrun grant (if any) ends with the activation
	overrun_pile_in_unit_11e = ""
	var _of_unit = GameState.get_unit(unit_id)
	if not _of_unit.is_empty():
		_of_unit.get("flags", {}).erase("selected_for_overrun_fight")

	# Units engaged mid-phase (pile-ins, overruns) become eligible to fight
	# — keep the 12.08 consolidation-eligibility stamps cumulative.
	_stamp_fight_eligibility_11e()

	# Codex: Adeptus Custodes VIGIL UNENDING / IN AURAMITE CLAD end "until that
	# enemy unit has attacked" (CustodesCodex11e.gd).
	_cus11e_codex().on_unit_has_attacked(unit_id)
	# Codex: Space Marines (11e) Space Wolves HEROIC RESOLVE ends "until that enemy unit has attacked" (SWCodex11e.gd).
	load("res://scripts/codex/space_wolves/SWCodex11e.gd").on_unit_has_attacked(unit_id)
	# Codex: Space Marines (11e) ARMOUR OF CONTEMPT ends "until that enemy unit has attacked" (SMCodex11e.gd).
	load("res://scripts/codex/space_marines/SMCodex11e.gd").on_unit_has_attacked(unit_id)
	# Codex: Adeptus Custodes INDOMITABLE GUARDIANS (CustodesCodex11e.gd): the
	# opponent's enemy_has_fought window ("Your opponent's Fight phase, when an
	# enemy unit has fought") opens before the next selection / Counter-Offensive.
	var fought_owner := int(get_unit(unit_id).get("owner", 0))
	# WP-S4 (SWAbilities11e): the fighter's own unit_has_fought window first —
	# Space Wolves HAMMER BLOW ("In the Fight phase, when this unit has fought").
	var sw_uhf: Array = _sw11e_abilities().unit_has_fought_entries(unit_id, _sw11e_abilities().melee_hit_unit_ids(_sw11e_fought_assignments, dice_log.slice(mini(_sw11e_dice_mark, dice_log.size()))))
	# WP-M4c RIGHTEOUS FURY (Captain Titus): "when this unit has fought" — Titus heals D3 (2D3 after a kill) (SMAbilitiesC, diffs applied).
	changes.append_array(load("res://scripts/codex/space_marines/SMAbilitiesC.gd").on_unit_has_fought(unit_id))
	_sw11e_fought_assignments = []
	# Codex: Space Marines (11e) TRANSHUMAN SWIFTNESS (SMCodex11e.gd): "Fight phase, when an enemy unit has
	# fought" — either player's Fight phase, so the window also opens for the active player.
	var sm11e_ehf: bool = GameConstants.edition >= 11 and fought_owner != GameState.get_active_player() and _sm11e_codex().player_has_window_stratagem(2 if fought_owner == 1 else 1, "enemy_has_fought")
	if GameConstants.edition >= 11 and (fought_owner == GameState.get_active_player() or not sw_uhf.is_empty() or sm11e_ehf):
		var ehf_decider := 2 if fought_owner == 1 else 1
		var ehf_ctx := {"phase": "fight", "enemy_unit_id": unit_id, "attacker_unit_id": unit_id}
		var ehf_entries: Array = sw_uhf.duplicate()
		if fought_owner == GameState.get_active_player() or sm11e_ehf:
			ehf_entries.append({"player": ehf_decider, "window_id": "enemy_has_fought", "ctx": ehf_ctx})
		if open_stratagem_windows(ehf_entries, "_cus11e_resume_after_enemy_has_fought", ehf_ctx):
			log_phase_message("Waiting for Player %d's %s decision (%s has fought)" % [get_pending_stratagem_window_decider(), str(ehf_entries.map(func(e): return e.window_id)), unit_id])
			changes.append_array(consume_window_diffs())
			final_result["changes"] = changes
			return final_result
		var ehf_sync := consume_window_diffs()
		if not ehf_sync.is_empty():
			changes.append_array(ehf_sync)
			final_result["changes"] = changes
	return _after_enemy_has_fought_window(unit_id, final_result)

## Resume point for the enemy_has_fought window (BasePhase framework).
func _cus11e_resume_after_enemy_has_fought(ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	return _after_enemy_has_fought_window(str(ctx.get("enemy_unit_id", "")), create_result(true, []))

## Everything after "this unit has fought" once the enemy_has_fought window
## has closed: the Counter-Offensive offer, then the next fighter selection.
func _after_enemy_has_fought_window(unit_id: String, final_result: Dictionary) -> Dictionary:
	# Counter-Offensive window (11e 15.12) — "Fight step of your OPPONENT'S
	# Fight phase, just after an enemy unit has resolved its attacks".
	var fought_unit = get_unit(unit_id)
	var fought_unit_owner = int(fought_unit.get("owner", 0))
	var opponent_player = 2 if fought_unit_owner == 1 else 1
	var co_check = StratagemManager.is_counter_offensive_available(opponent_player)
	# 11e restricts the window to the non-active player: during your own Fight
	# phase you cannot counter-offensive (10e's version had no such clause —
	# "Fight phase, just after an enemy unit has fought" — and this offered the
	# active player the stratagem whenever a defender's unit swung back).
	if GameConstants.edition >= 11 and opponent_player == GameState.get_active_player():
		co_check = {"available": false, "reason": "COUNTER-OFFENSIVE is only usable in your opponent's Fight phase (15.12)"}
	var co_eligible = []
	if co_check.available:
		# 15.12 TARGET is "one friendly unit that is eligible to fight" — hand
		# the sequencer's live 12.04 candidate list over rather than re-deriving
		# a 10e "in Engagement Range" approximation. It is already 19.01-folded,
		# so attached CHARACTERs arrive through their bodyguard's entry.
		var co_fight_eligible = null
		if sequencer_11e != null:
			co_fight_eligible = sequencer_11e.eligible_units(GameState.state, opponent_player, false)
		co_eligible = StratagemManager.get_counter_offensive_eligible_units(
			opponent_player, units_that_fought, game_state_snapshot, co_fight_eligible
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

# ============================================================================
# Codex: Orks (11e) — FIGHT ON DEATH (core 05.04.05) for ORKS IS NEVER BEATEN,
# TOO ARROGANT TO DIE and CRAZED RAMPAGE (OrkCodexFight marks the unit with
# FLAG_FOD_MODE). "When a model in your unit is destroyed, if your unit has not
# been selected to fight this phase, roll one D6 (+mod): on a 4+, do not remove
# that model from the battlefield. When your unit has fought, or at the end of
# the phase (whichever comes first), that model is removed."
#
# A kept model is DESTROYED but on the battlefield: alive=true, 0 wounds left,
# its index listed in the unit's FLAG_FOD_PENDING. It still fights with its
# unit (fight eligibility / attack resolution read alive models) and nothing
# can be allocated to it any more (RulesEngine.model_can_be_allocated,
# Allocation.build_groups). Rules triggered by its destruction (kill / VP
# accounting, Deadly Demise…) resolve when it is removed (_check_kill_diffs on
# the removal diffs) — 05.04.05: "Any rules triggered by those models being
# destroyed are resolved, and then those destroyed models are removed."
# ============================================================================

func _ork11e_group_selected_to_fight(unit_id: String) -> bool:
	for gid in _fight_group_ids(unit_id):
		if _ork11e_selected_to_fight.has(gid) or gid in units_that_fought:
			return true
	return false

## Roll for every model destroyed by `changes` (alive=false set diffs) whose
## unit is under a Fight On Death stratagem and has not been selected to fight
## this phase. A pass rewrites that diff to alive=true (in place — the caller
## applies `changes` afterwards; set ops are idempotent, so a board the
## RulesEngine already mutated in place is restored too) and appends the
## unit's updated FLAG_FOD_PENDING list. Each model is rolled for once.
func _ork11e_fod_intercept(changes: Array) -> void:
	if changes.is_empty():
		return
	var units: Dictionary = GameState.state.get("units", {})
	var new_pending: Dictionary = {}  # unit_id -> Array[int]
	var ork11e_ard_sources: Dictionary = {}  # 'Ard as Nails keeps (WP-O34): unit_id -> FOD source label
	for diff in changes:
		if typeof(diff) != TYPE_DICTIONARY or str(diff.get("op", "")) != "set":
			continue
		var path := str(diff.get("path", ""))
		if not path.ends_with(".alive") or diff.get("value", true) != false:
			continue
		var parts := path.split(".")
		if parts.size() != 5 or parts[0] != "units" or parts[2] != "models":
			continue
		var uid := parts[1]
		var unit: Dictionary = units.get(uid, {})
		var uflags: Dictionary = unit.get("flags", {})
		var mode := str(uflags.get(OrkCodexFight.FLAG_FOD_MODE, ""))
		# Codex: Orks (11e) Brute Bosses — 'Ard as Nails (WP-O34): a destroyed WARBOSS model fights on (3+, +1 riled up).
		var ard := mode == "" and Ork11eDetachments.ard_as_nails_applies(unit)
		if ard:
			mode = Ork11eDetachments.ARD_AS_NAILS_MODE
		# WP-S4 (SWAbilities11e): Space Wolves Murder-maker / Anvil of Endurance / Heroic Last Stand.
		var sw_fod: Dictionary = _sw11e_abilities().fod_rule(uid, int(parts[3])) if mode == "" else {}
		if sw_fod.is_empty() and mode == "":
			sw_fod = load("res://scripts/codex/space_marines/SMAbilitiesC.gd").fod_rule(uid, int(parts[3]))  # WP-M4c Honour of Ultramar (Captain Titus, 2+)
		if not sw_fod.is_empty():
			mode = "sw11e"
		if mode == "":
			continue
		var idx := int(parts[3])
		var key := "%s:%d" % [uid, idx]
		if _ork11e_fod_rolled.has(key) or diff.get("ork11e_fod_rolled", false):
			continue
		var live_pending: Array = uflags.get(OrkCodexFight.FLAG_FOD_PENDING, [])
		if idx in live_pending:
			continue  # the removal of a model this mechanic kept — not a new destruction
		_ork11e_fod_rolled[key] = true
		# The marker travels with the diff (APPLY_MELEE_SAVES summary from the
		# defender's AllocationGroupOverlay, network relay) so no other peer or
		# later pass rolls for this model again.
		diff["ork11e_fod_rolled"] = true
		var source := str(uflags.get(OrkCodexFight.FLAG_FOD_SOURCE, "Fight On Death"))
		if ard:
			source = "'Ard as Nails"
		elif not sw_fod.is_empty():
			source = str(sw_fod.get("source", source))  # WP-S4
		var models: Array = unit.get("models", [])
		var label := str(unit.get("meta", {}).get("name", uid))
		if idx >= 0 and idx < models.size() and models.size() > 1:
			label = "%s of %s" % [RulesEngine.get_model_display_label(models[idx], unit), label]
		if _ork11e_group_selected_to_fight(uid):
			log_phase_message("%s: %s destroyed — its unit has already been selected to fight this phase, so no roll (removed)" % [source, label])
			continue
		var rng = RulesEngine.make_rng()
		var roll: int = int(rng.roll_d6(1)[0])
		var mod_info: Dictionary = Ork11eDetachments.ard_as_nails_roll_modifier(unit) if ard else OrkCodexFight.fod_roll_modifier(uid)
		var fod_pass: int = Ork11eDetachments.ARD_AS_NAILS_PASS if ard else OrkCodexFight.FOD_PASS
		# Codex: Adeptus Custodes DUTY UNTO DEATH (CustodesCodex11e.gd): same mechanic, 3+ (+1 for a CHARACTER model).
		if not ard and _cus11e_codex().is_fod_mode(mode):
			mod_info = _cus11e_codex().fod_roll(uid, idx)
			fod_pass = int(mod_info.get("pass", fod_pass))
		# Codex: Space Marines (11e) A WORTHY DEATH (SMCodex11e.gd): same mechanic, 4+, no modifier.
		if not ard and _sm11e_codex().is_fod_mode(mode):
			mod_info = _sm11e_codex().fod_roll(uid, idx)
		# Codex: Space Marines (11e) WP-M3b DUTY IN DEATH (SMCodexB.gd): 4+, +1 with the assault doctrine.
		if not ard and load("res://scripts/codex/space_marines/SMCodexB.gd").is_fod_mode(mode):
			mod_info = load("res://scripts/codex/space_marines/SMCodexB.gd").fod_roll(uid, idx)
			fod_pass = int(mod_info.get("pass", fod_pass))
		# WP-S4: the Space Wolves rule's own threshold (Heroic Last Stand 2+, the others 4+), no modifier.
		if not sw_fod.is_empty():
			mod_info = {"mod": 0, "note": ""}
			fod_pass = int(sw_fod.get("pass", fod_pass))
		var mod := int(mod_info.get("mod", 0))
		var total := roll + mod
		var kept := total >= fod_pass
		var msg := "%s: %s destroyed — D6 %d%s = %d (%d+ needed): %s" % [
			source, label, roll, (" %s" % str(mod_info.get("note", ""))) if mod != 0 else "", total, fod_pass,
			"NOT REMOVED — it stays on the battlefield until its unit has fought or the end of the phase" if kept else "removed"]
		log_phase_message(msg)
		DebugLogger.info(str("FightPhase: [ork11e FOD] " + msg))
		var raw_needed := clampi(fod_pass - mod, 1, 7)
		if kept and (ard or not sw_fod.is_empty()):  # WP-S4: the Space Wolves source names the removal line too
			ork11e_ard_sources[uid] = source
		var dice_block := {"context": "ork11e_fight_on_death", "stratagem": source, "unit_id": uid, "model_index": idx,
			"rolls_raw": [roll], "rolls_modified": [total], "modifier": mod, "threshold": "%d+" % raw_needed,
			"successes": 1 if kept else 0, "kept": kept, "message": msg}
		dice_log.append(dice_block)
		emit_signal("dice_rolled", dice_block)
		var gel = get_node_or_null("/root/GameEventLog")
		if gel:
			gel.add_combat_result("  " + msg)
		if kept:
			diff["value"] = true
			# Remember whose attacks destroyed it: the removal happens later (in
			# this unit's own activation or at the end of the phase), and the
			# unit_destroyed / enemy_unit_has_attacked events must credit them.
			if active_fighter_id != "" and int(get_unit(active_fighter_id).get("owner", 0)) != int(unit.get("owner", 0)):
				_ork11e_fod_destroyer[uid] = active_fighter_id
			var plist: Array = new_pending.get(uid, live_pending.duplicate())
			if not idx in plist:
				plist.append(idx)
			new_pending[uid] = plist
	for uid in new_pending:
		changes.append({"op": "set", "path": "units.%s.flags.%s" % [uid, OrkCodexFight.FLAG_FOD_PENDING], "value": new_pending[uid]})
	for uid in ork11e_ard_sources:
		changes.append({"op": "set", "path": "units.%s.flags.%s" % [uid, OrkCodexFight.FLAG_FOD_SOURCE], "value": ork11e_ard_sources[uid]})

## Removal diffs for the models kept by Fight On Death in `unit_ids` (and
## their pending lists cleared). Returns [] when there is nothing to remove.
func _ork11e_fod_remove(unit_ids: Array, reason: String) -> Array:
	var diffs: Array = []
	var units: Dictionary = GameState.state.get("units", {})
	for uid_raw in unit_ids:
		var uid := str(uid_raw)
		var unit: Dictionary = units.get(uid, {})
		var pending: Array = unit.get("flags", {}).get(OrkCodexFight.FLAG_FOD_PENDING, [])
		if pending.is_empty():
			continue
		var models: Array = unit.get("models", [])
		var labels: Array = []
		for idx_raw in pending:
			var idx := int(idx_raw)
			if idx < 0 or idx >= models.size():
				continue
			_ork11e_fod_rolled["%s:%d" % [uid, idx]] = true
			diffs.append({"op": "set", "path": "units.%s.models.%d.alive" % [uid, idx], "value": false})
			labels.append(RulesEngine.get_model_display_label(models[idx], unit))
		diffs.append({"op": "set", "path": "units.%s.flags.%s" % [uid, OrkCodexFight.FLAG_FOD_PENDING], "value": []})
		if _ork11e_fod_destroyer.has(uid):
			_ev_destroyed_by[uid] = str(_ork11e_fod_destroyer[uid])
		var source := str(unit.get("flags", {}).get(OrkCodexFight.FLAG_FOD_SOURCE, "Fight On Death"))
		var msg := "%s: %d model(s) of %s removed from the battlefield (%s): %s" % [
			source, labels.size(), unit.get("meta", {}).get("name", uid), reason, ", ".join(labels)]
		log_phase_message(msg)
		var gel = get_node_or_null("/root/GameEventLog")
		if gel:
			gel.add_combat_result("  " + msg)
	return diffs

## End of the phase: every model still kept by Fight On Death is removed.
func _ork11e_fod_remove_all(reason: String) -> Array:
	var ids: Array = []
	for uid in GameState.state.get("units", {}):
		if not GameState.state.units[uid].get("flags", {}).get(OrkCodexFight.FLAG_FOD_PENDING, []).is_empty():
			ids.append(str(uid))
	return _ork11e_fod_remove(ids, reason)

# 11e 12.07-12.08: one consolidation move during the global Consolidate
# step. Applies the movement, marks the unit's single move used, and —
# for an Engaging Consolidation that tagged unfought enemy units — hands
# those units to the opponent to fight (12.08 AFTER MOVING) before the
# step continues.
func _process_consolidate_step_11e(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var movements = _fight_movements_from_action(action)
	var changes = []

	# 12.08 Objective Consolidation: the objective the player (or the AI) selected.
	var chosen_obj = str(action.get("chosen_objective", ""))
	var toward = " toward %s" % consolidation_objective_label_11e(chosen_obj) if chosen_obj != "" else ""
	if movements.is_empty():
		log_phase_message("[11e 12.07] %s consolidates%s — no models moved" % [unit_id, toward])
	else:
		log_phase_message("[11e 12.07] %s consolidates%s — %d model(s) moved" % [unit_id, toward, movements.size()])

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
	# Skip this unit and advance to next. 19.03: skipping an Attached unit
	# forfeits the WHOLE unit's fight — leaving its Leader unmarked would offer
	# him again as a fight of his own.
	for member_id in _fight_group_ids(str(action.unit_id)):
		if not member_id in units_that_fought:
			units_that_fought.append(member_id)
	active_fighter_id = ""

	# 11e: keep the sequencer's candidate list consistent — a skipped unit
	# forfeits its fight and must not be re-offered forever.
	if sequencer_11e != null:
		sequencer_11e.mark_fought(action.unit_id, GameState.state)
		# A skipped activation also forfeits any 12.06 overrun grant
		if overrun_pile_in_unit_11e == action.unit_id:
			overrun_pile_in_unit_11e = ""
		var _sk_unit = GameState.get_unit(action.unit_id)
		if not _sk_unit.is_empty():
			_sk_unit.get("flags", {}).erase("selected_for_overrun_fight")

	var skip_changes: Array = []
	# The activation is over: record it for every component (synced to a
	# multiplayer client, whose FightSequencer reads fight_done_turn).
	for member_id in _fight_group_ids(str(action.unit_id)):
		skip_changes.append({"op": "set", "path": "units.%s.flags.has_fought" % member_id, "value": true})
	skip_changes.append_array(_fight_done_changes_11e(str(action.unit_id)))
	# Codex: Orks (11e) Fight On Death: an activation ended by SKIP_UNIT still
	# means the unit has fought (#916: has_fought / fight_done above), so the
	# models it kept on the battlefield are removed now — the same point as
	# _finish_fight_activation_11e. Applied early so the next selection, the
	# p.74 pass check and the Consolidate step see the board without them.
	var sk_fod_changes := _ork11e_fod_remove(_fight_group_ids(str(action.unit_id)), "has fought")
	if not sk_fod_changes.is_empty():
		PhaseManager.apply_state_changes(sk_fod_changes)
		skip_changes.append_array(sk_fod_changes)
	skip_changes.append_array(Ork11eDetachments.on_unit_has_fought(str(action.unit_id)))  # Codex: Orks (11e) Try Dat Button! (WP-O34)

	# Switch to next player
	_switch_selecting_player()

	log_phase_message("Skipped unit %s" % action.unit_id)

	# Request next fight selection; when nobody is left and the 11e global
	# Consolidate step is running (a forced fight was skipped), resume it.
	var result = create_result(true, skip_changes)
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
	# Codex: Adeptus Custodes (11e) Heralds of the Throne (Emissaries
	# Imperatus): friendly ADEPTUS CUSTODES units have Fights First (WP-C46).
	if not has_fights_first and _cus11e_det().has_fights_first(unit):
		has_fights_first = true

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
		for player_key in ["1", "2"]:
			var out: Array = []
			for unit_id in sequencer_11e.eligible_units(GameState.state, int(player_key), false):
				# 19.03: an Attached unit is Fights First when ANY component is,
				# so partition with the same group predicate eligible_units used
				# — otherwise the pair showed up in BOTH sections.
				if not sequencer_11e.group_is_fights_first(unit_id, GameState.state):
					out.append(unit_id)
			d[player_key] = out
	return d

func _combatants_11e() -> Array:
	# Units that are or were in the fight this phase, for UI display (fighter
	# list + fight-order signals): still-eligible first, then already-fought.
	# 19.03: ONE entry per Attached unit — an attached CHARACTER is folded into
	# his bodyguard's row, so the FIGHT SEQUENCE panel no longer listed "Boyz"
	# and "Warboss" as two separate combatants when they swing together.
	var out: Array = []
	if sequencer_11e == null:
		return out
	for unit_id in GameState.state.get("units", {}):
		if RulesEngine.is_attached_character(unit_id, GameState.state):
			continue
		if sequencer_11e.group_eligible_to_fight(unit_id, GameState.state):
			out.append(unit_id)
	for unit_id in units_that_fought:
		if RulesEngine.is_attached_character(unit_id, GameState.state):
			continue
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
		"units_that_fought": units_that_fought,
		# p.74 "Eligible to fight, but unable to fight": the selecting player
		# may pass only when every eligible unit of theirs is >5" from all
		# enemy units. The selection panel shows a Pass button off this flag.
		"can_pass": sequencer_11e != null and sequencer_11e.can_pass(GameState.state, current_selecting_player)
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
		"units_that_fought": units_that_fought,
		# p.74 "Eligible to fight, but unable to fight": the selecting player
		# may pass only when every eligible unit of theirs is >5" from all
		# enemy units. The selection panel shows a Pass button off this flag.
		"can_pass": sequencer_11e != null and sequencer_11e.can_pass(GameState.state, current_selecting_player)
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
	# selectable_units: a player who has passed (p.74) is not offered their
	# units again until the sequence returns to them.
	for unit_id in sequencer_11e.selectable_units(GameState.state, current_selecting_player, only_ff):
		var unit = get_unit(unit_id)
		if not unit.is_empty():
			# 19.03: ONE row for the whole Attached unit — "Boyz + Warboss",
			# offering both components' melee weapons, because selecting it
			# activates them together.
			eligible[unit_id] = {
				"name": _fight_attached_display_name(unit_id),
				"weapons": _fight_group_melee_weapons(unit_id),
				"targets": _get_eligible_melee_targets(unit_id)
			}
	return eligible

# Melee weapons of the whole Attached unit, keyed so the caller can still tell
# which component a model belongs to: the chosen unit's own entries keep their
# plain "m<i>" keys, an attached character's are prefixed "<unit_id>:" (the same
# composite-bearer convention RulesEngine.get_unit_weapons uses for shooting,
# where the Attached unit has fired as one unit all along).
func _fight_group_melee_weapons(unit_id: String) -> Dictionary:
	var out = RulesEngine.get_unit_melee_weapons(unit_id, game_state_snapshot).duplicate(true)
	for char_id in _fight_attached_char_ids(unit_id):
		var char_weapons = RulesEngine.get_unit_melee_weapons(char_id, game_state_snapshot)
		for key in char_weapons:
			out["%s:%s" % [char_id, str(key)]] = char_weapons[key]
	return out

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
	# 19.03: the ATTACKER is the whole Attached unit too — an enemy reachable
	# only by the attached leader's model is a target for this activation.
	var actor_group = {"models": RulesEngine.attached_unit_models(unit_id, game_state_snapshot)}

	for other_unit_id in all_units:
		var other_unit = all_units[other_unit_id]
		var other_owner = other_unit.get("owner", 0)
		if other_owner == unit_owner:
			continue

		# 19.02/19.03: while a CHARACTER is attached to a bodyguard the two are
		# ONE Attached unit, so the leader is NOT a target of its own — the
		# bodyguard entry stands for the whole Attached unit and the allocation
		# rules (05.04) are what reach the leader. Without this the AI happily
		# picked the attached Warboss and every wound landed on him while his
		# Boyz stood untouched.
		if RulesEngine.is_attached_character(other_unit_id, game_state_snapshot):
			log_phase_message("[19.02] Target %s excluded: attached CHARACTER — fight %s (the Attached unit) instead" % [
				other_unit_id, RulesEngine.attached_unit_target_id(other_unit_id, game_state_snapshot)])
			continue

		# Engagement range is measured against the WHOLE Attached unit
		# (bodyguard + attached characters' models): a unit engaged only with
		# the attached leader's model is still engaged with the unit.
		var other_group = {"models": RulesEngine.attached_unit_models(other_unit_id, game_state_snapshot)}
		if _units_in_engagement_range(actor_group, other_group):
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

# The subset of `candidate_ids` that `component_id`'s OWN models are within
# Engagement Range of — i.e. exactly the targets an ASSIGN_ATTACKS naming this
# component will pass _validate_assign_attacks against.
#
# _get_eligible_melee_targets answers "what may this ACTIVATION attack", and
# measures the actor as the whole Attached unit (19.03). That is the right
# question for the activation, and the WRONG one for any single component:
# 11e Fight ("Select Targets") requires each target to be engaged with the
# model carrying the weapon, and an Attached unit's components stand in
# different places. A Custodian Guard led by a Blade Champion can have the
# bodyguard locked with one Ork mob and the Champion locked with another —
# the activation may attack both, but neither component may attack both.
#
# Reported bug: the attack dialog offered the whole activation's target list to
# every section, so "Best Weapons ✨" (which points every section at the ONE
# selected target) built a plan whose bodyguard half the engine then rejected
# with "not within engagement range" — on a unit plainly still in combat.
# Callers narrow with this first; the engine gate stays as-is.
# Empty `candidate_ids` means "the whole activation's list".
func melee_targets_for_component(component_id: String, candidate_ids: Array = []) -> Array:
	var out: Array = []
	var component = get_unit(component_id)
	if component.is_empty():
		return out
	var candidates: Array = candidate_ids
	if candidates.is_empty():
		candidates = _get_eligible_melee_targets(component_id).keys()
	for tid in candidates:
		var target_id := str(tid)
		var target_models: Array = RulesEngine.attached_unit_models(target_id, game_state_snapshot)
		if target_models.is_empty():
			continue
		if _units_in_engagement_range(component, {"models": target_models}):
			out.append(target_id)
	return out

# Clamp `preferred_target_id` to something `component_id` may legally attack:
# the preference when it is reachable, otherwise the first reachable candidate,
# otherwise "" (this component contributes nothing to the activation).
func reachable_melee_target_for(component_id: String, preferred_target_id: String, candidate_ids: Array = []) -> String:
	var reachable := melee_targets_for_component(component_id, candidate_ids)
	if reachable.is_empty():
		return ""
	if preferred_target_id != "" and preferred_target_id in reachable:
		return preferred_target_id
	return str(reachable[0])

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

## T09 (BasePhase.has_unit_acted_this_phase): a unit has acted in the Fight
## phase once it has fought — selected to fight and its attacks resolved, or
## passed over (units_that_fought, kept by this instance; flags.has_fought,
## which also reaches a network client). Either player's units, since both
## fight. has_fought only means this phase here: it is cleared for both
## players at every turn boundary.
func has_unit_acted_this_phase(unit_id: String) -> bool:
	if unit_id in units_that_fought:
		return true
	return _t09_unit_flag(unit_id, "has_fought")

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

# 19.03: the component units of the Attached unit that is fighting as ONE unit
# in a single activation — the chosen unit plus its attached characters. Same
# membership as _fight_move_group_ids (pile in / consolidate already move as
# one); named separately because the ATTACK side reads it too and the two are
# conceptually different rules (12.02/12.07 vs 12.05).
#
# The components stay separate unit dicts: each keeps its own stats, abilities,
# weapons and model indices, and RulesEngine resolves every assignment against
# `assignment.attacker` rather than the activation's actor. So one activation
# simply carries assignments from more than one component — no virtual merged
# unit, and no per-component activation for the enemy to interleave with.
func _fight_group_ids(unit_id: String) -> Array:
	if unit_id == "":
		return []
	return _fight_move_group_ids(unit_id)

# True when unit_id is part of the Attached unit currently activated. Attack
# assignments may name any component of it (the Boyz' choppas AND their
# Warboss's power klaw land in the same activation's batch).
func _is_in_active_fight_group(unit_id: String) -> bool:
	return unit_id in _fight_group_ids(active_fighter_id)

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

# ============================================================================
# Codex: Adeptus Custodes (WP-C5, CustodesCodex11e.gd) — the unit chosen in the
# Pile In / Consolidate step opens its stratagem window first:
#   unit_selected_to_pile_in      LIGHTNING WRATH (pile-in move up to D3+3")
#   unit_selected_to_consolidate  EMPEROR'S DOMAIN (objective mode)
# The FightController sends CUS11E_SELECT_*_UNIT only when the unit's owner
# has such a stratagem (CustodesCodex11e.player_has_window_stratagem) and
# starts the move when cus11e_step_unit_ready fires (at once, or when the
# window closes).
# ============================================================================

signal cus11e_step_unit_ready(kind: String, unit_id: String, max_inches: float)

var _cus11e_step_asked: Dictionary = {}  # "<pile_in|consolidate>:<unit_id>" -> true: its window was opened this phase

## Has this unit's step window already been opened this phase (AIDecisionMaker
## asks before it computes the move; a re-selection skips the window).
func cus11e_step_unit_asked(kind: String, unit_id: String) -> bool:
	return _cus11e_step_asked.has("%s:%s" % [kind, unit_id])

func _cus11e_validate_step_unit(action: Dictionary) -> Dictionary:
	var unit_id := str(action.get("unit_id", ""))
	var unit := get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit %s not found" % unit_id]}
	if str(action.get("type", "")) == "CUS11E_SELECT_PILE_IN_UNIT":
		if pile_in_step_11e != PileInStep11e.ACTIVE:
			return {"valid": false, "errors": ["Not in the Pile In step"]}
		if int(unit.get("owner", 0)) != piling_in_player_11e:
			return {"valid": false, "errors": ["Not your half of the Pile In step (Player %d piles in)" % piling_in_player_11e]}
		if not unit_id in _pile_in_eligible_units_11e(piling_in_player_11e):
			return {"valid": false, "errors": ["%s cannot pile in now" % unit_id]}
	else:
		if consolidation_step_11e != ConsolidationStep11e.ACTIVE:
			return {"valid": false, "errors": ["Not in the Consolidate step"]}
		if int(unit.get("owner", 0)) != consolidating_player_11e:
			return {"valid": false, "errors": ["Not your half of the Consolidate step (Player %d consolidates)" % consolidating_player_11e]}
		if not unit_id in _consolidation_eligible_units_11e(consolidating_player_11e):
			return {"valid": false, "errors": ["%s cannot consolidate now" % unit_id]}
	return {"valid": true, "errors": []}

func _cus11e_process_step_unit(action: Dictionary) -> Dictionary:
	var unit_id := str(action.get("unit_id", ""))
	var pile := str(action.get("type", "")) == "CUS11E_SELECT_PILE_IN_UNIT"
	var window_id := "unit_selected_to_pile_in" if pile else "unit_selected_to_consolidate"
	var owner := int(get_unit(unit_id).get("owner", 0))
	var ctx := {"phase": "fight", "unit_id": unit_id, "step_kind": "pile_in" if pile else "consolidate"}
	var asked_key := "%s:%s" % [str(ctx.step_kind), unit_id]
	if _cus11e_step_asked.has(asked_key):
		return _cus11e_step_unit_ready(str(ctx.step_kind), unit_id)
	_cus11e_step_asked[asked_key] = true
	if open_stratagem_window(owner, window_id, ctx, "_cus11e_resume_after_step_unit_window"):
		log_phase_message("Waiting for Player %d's %s stratagem decision (%s)" % [owner, window_id, unit_id])
		return create_result(true, consume_window_diffs())
	var res := _cus11e_step_unit_ready(str(ctx.step_kind), unit_id)
	var sync := consume_window_diffs()
	if not sync.is_empty():
		res["changes"] = sync
	return res

func _cus11e_resume_after_step_unit_window(ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	return _cus11e_step_unit_ready(str(ctx.get("step_kind", "pile_in")), str(ctx.get("unit_id", "")))

## The chosen unit may now make its move: tell the controller (signal + result).
func _cus11e_step_unit_ready(kind: String, unit_id: String) -> Dictionary:
	var inches := 3.0
	if kind == "pile_in":
		inches = maxf(3.0, float(_cus11e_codex().pile_in_inches(unit_id)))
	log_phase_message("%s is ready to %s (up to %.0f\")" % [unit_id, "pile in" if kind == "pile_in" else "consolidate", inches])
	emit_signal("cus11e_step_unit_ready", kind, unit_id, inches)
	return create_result(true, [], "", {"cus11e_step_unit_ready": {"kind": kind, "unit_id": unit_id, "max_inches": inches}})

# Enter the Pile In step (12.02) — the fight phase opens here at e11:
# both players make pile-in moves with the eligible units they choose,
# the player whose turn it is first.
func _begin_pile_in_step_11e() -> Dictionary:
	pile_in_step_11e = PileInStep11e.ACTIVE
	pile_in_done_players_11e = {}
	piling_in_player_11e = GameState.get_active_player()
	log_phase_message("[11e 12.02] PILE IN step begins — Player %d (active) first" % piling_in_player_11e)
	emit_signal("subphase_transition", "START_OF_FIGHT_PHASE", "PILE_IN")
	return _advance_pile_in_step_11e(create_result(true, []))

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
		# 12.04 "engaged at the start of this step" means the Fight step, i.e.
		# after the pile-in moves just made — retake the snapshot the
		# sequencer took at phase entry, then re-stamp 12.08 eligibility
		# (cumulative) for units the pile-ins brought into combat.
		if sequencer_11e != null:
			sequencer_11e.snapshot_step_start(GameState.state)
			var engaged_ids: Array = []
			for snap_id in sequencer_11e.engaged_at_step_start:
				if sequencer_11e.engaged_at_step_start[snap_id]:
					engaged_ids.append(snap_id)
			log_phase_message("[11e 12.04] Fight step engagement snapshot (after Pile In): %s" % str(engaged_ids))
			_stamp_fight_eligibility_11e()
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

	# END_FIGHT only reaches here once the Fight step is over (12.04): every
	# eligible unit has fought, or the units still eligible belong to players
	# who passed under "Eligible to fight, but unable to fight" (p.74). Those
	# passed units did not fight — mark them so the sequencer doesn't re-offer
	# them as 12.08 forced fights mid-consolidation, and clear the passes so a
	# 12.08 forced fight can still be selected by its owner.
	var passed_done_changes: Array = []
	if sequencer_11e != null:
		for unit_id in GameState.state.get("units", {}):
			if sequencer_11e.eligible_to_fight(unit_id, GameState.state):
				log_phase_message("[11e 12.07] %s did not fight (its player passed, p.74)" % unit_id)
				sequencer_11e.mark_fought(unit_id)
				passed_done_changes.append_array(_fight_done_changes_11e(unit_id, false))
		sequencer_11e.passed = {}
	if not passed_done_changes.is_empty():
		PhaseManager.apply_state_changes(passed_done_changes)

	consolidating_player_11e = GameState.get_active_player()
	log_phase_message("[11e 12.07] CONSOLIDATE step begins — Player %d (active) first" % consolidating_player_11e)
	emit_signal("subphase_transition", _subphase_string_11e(), "CONSOLIDATE")
	return _advance_consolidation_step_11e(create_result(true, passed_done_changes))

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
		var default_objective = ""
		if tmpl != null:
			var folded = _fight_folded_board(unit_id, GameState.state)
			mode = str(tmpl.select_mode(unit_id, folded).mode)
			# 12.08 Objective mode: name the marker the unit will default to
			# (the closest selectable one) on its picker row.
			if mode == "objective":
				var cands = tmpl.objective_candidates(unit_id, folded)
				default_objective = str(cands[0]) if not cands.is_empty() else ""
		units[unit_id] = {
			"name": _fight_attached_display_name(unit_id),
			"mode": mode,
			"objective": default_objective,
			"objective_label": consolidation_objective_label_11e(default_objective),
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

			# The way BACK: nothing is committed yet, so the player may undo a
			# mis-picked activation and choose a different unit. Listed here so
			# the escape hatch is discoverable in get_legal_actions, not just as
			# a button on the attack dialog.
			if confirmed_attacks.is_empty() and staged_fight_state.is_empty() and not awaiting_melee_saves:
				actions.append({
					"type": "CANCEL_FIGHTER_SELECTION",
					"unit_id": active_fighter_id,
					"player": int(get_unit(active_fighter_id).get("owner", get_current_player())),
					"description": "Pick a different unit to fight instead of %s" % active_fighter_id
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
	
	# END_FIGHT in the Fight step (12.04) is offered ONLY when it is legal:
	#  - the step is over (every eligible unit has been selected to fight, or
	#    the rest belong to players who passed), or
	#  - the selecting player may PASS because every one of their eligible
	#    units is more than 5" from all enemy units (p.74 "Eligible to fight,
	#    but unable to fight").
	# Fighting is mandatory — a player can never decline an eligible fight.
	var end_fight_status = get_end_fight_status()
	if active_fighter_id == "" and not awaiting_sweeping_advance and not awaiting_acrobatic_escape:
		if end_fight_status.step_over:
			log_phase_message("Adding END_FIGHT action - fight step complete (11e sequencer)")
			actions.append({
				"type": "END_FIGHT",
				"description": "End Fight Phase"
			})
		elif end_fight_status.can_pass:
			log_phase_message("Adding END_FIGHT (pass) for Player %d - all eligible units >5\" from enemies (p.74)" % end_fight_status.selecting_player)
			actions.append({
				"type": "END_FIGHT",
				"player": end_fight_status.selecting_player,
				"pass": true,
				"description": "Pass — every eligible unit is more than 5\" from all enemy units"
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
		return GameConstants.engagement_range_inches()
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if terrain_manager and terrain_manager.has_method("get_engagement_range_for_positions"):
		return terrain_manager.get_engagement_range_for_positions(pos1, pos2)
	return GameConstants.engagement_range_inches()

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

				# Settings › Gameplay › vehicle collision override (see
				# SettingsService): skip the pair if either side is a VEHICLE.
				var mover_skips_collision := SettingsService.unit_skips_collision(route.unit_id)

				# Check against all other models
				for check_unit_id in all_units:
					if mover_skips_collision or SettingsService.unit_skips_collision(check_unit_id):
						continue
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
	# 19.03: on an ATTACHED unit the stratagem is the CHARACTER's — [PRECISION]
	# belongs on the components that actually have the keyword, so the leader's
	# attacks can pick out an enemy CHARACTER while his bodyguard's cannot.
	# (A lone CHARACTER unit is its own only component, so this is unchanged
	# for every unattached leader.)
	var precision_changes: Array = []
	for component_id in _fight_group_ids(unit_id):
		if _unit_has_keyword(get_unit(component_id), "CHARACTER"):
			precision_changes.append({"op": "set",
				"path": "units.%s.flags.%s" % [component_id, EffectPrimitivesData.FLAG_PRECISION_MELEE],
				"value": true})
	if precision_changes.is_empty():
		precision_changes.append({"op": "set",
			"path": "units.%s.flags.%s" % [unit_id, EffectPrimitivesData.FLAG_PRECISION_MELEE],
			"value": true})
	PhaseManager.apply_state_changes(precision_changes)

	# The fight itself
	var ec_result = _proceed_to_fight_moves(unit_id)
	# Merge diffs from stratagem result
	if not strat_result.get("diffs", []).is_empty():
		var merged_changes = strat_result.get("diffs", [])
		merged_changes.append_array(ec_result.get("changes", []))
		ec_result["changes"] = merged_changes
	return ec_result

func _process_decline_epic_challenge(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", active_fighter_id)
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)

	log_phase_message("Player declined EPIC CHALLENGE for %s" % unit_name)

	# The fight itself
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
		# 19.03: engagement is the ATTACHED unit's — a bodyguard engaged only
		# through its Leader's model (or vice versa) is engaged, and fights a
		# normal fight. Checking unit_id's own models alone granted the
		# bodyguard a spurious overrun pile-in. Same fold as
		# FightSequencer.select_to_fight.
		var engaged_now := false
		var engaged_at_start := false
		for component_id in RulesEngine.attached_unit_component_ids(unit_id, GameState.state):
			if RulesEngine.is_unit_engaged(component_id, GameState.state):
				engaged_now = true
			if sequencer_11e.engaged_at_step_start.get(component_id, false):
				engaged_at_start = true
		overrun_available = (not engaged_now) or not engaged_at_start
		log_phase_message("[11e 12.05/12.06] %s fight check — Attached unit engaged now: %s, at step start: %s" % [unit_id, engaged_now, engaged_at_start])
	# 12.06 grants ONE additional pile-in per unit per phase — a cancelled and
	# re-made selection re-enters here, so an already-spent move stays spent.
	if GameState.get_unit(unit_id).get("flags", {}).get("overrun_pile_in_made_this_phase", false):
		overrun_available = false
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

	# 19.01: an Attached unit is a single unit — its CHARACTER has no activation
	# of his own, so the bodyguard's id is the only legal selection here.
	if _fight_is_attached_character(unit_id):
		errors.append("%s is an attached character — select its bodyguard; the Attached unit counter-offensives as one (19.01)" % unit_id)
		return {"valid": false, "errors": errors}

	# The Attached unit fights ONCE: any component being marked spends it.
	for gid in _fight_group_ids(unit_id):
		if gid in units_that_fought:
			errors.append("Unit has already fought this phase")
			return {"valid": false, "errors": errors}

	# 11e 15.12 TARGET: "one friendly unit that is eligible to fight" (12.04 —
	# engaged, engaged at the start of the step, or charged this turn). The 10e
	# version demanded Engagement Range specifically; keep that as the fallback
	# for the sequencer-less path only.
	if sequencer_11e != null:
		if not sequencer_11e.group_eligible_to_fight(unit_id, GameState.state):
			errors.append("Unit is not eligible to fight (12.04)")
			return {"valid": false, "errors": errors}
	elif not _is_unit_in_combat(unit):
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
	# 19.03: an Attached unit counter-offensives as one — mark every component.
	if sequencer_11e != null:
		sequencer_11e.mark_fought(unit_id, GameState.state)

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

func _end_fight_half_is_scoped() -> bool:
	var nm = get_node_or_null("/root/NetworkManager")
	return nm != null and nm.has_method("is_networked") and nm.is_networked()

func _validate_end_fight(action: Dictionary) -> Dictionary:
	# 12.02 / 12.07: during the global Pile In and Consolidate steps END_FIGHT
	# ends the current player's half — both moves are optional per unit.
	# In multiplayer each peer sends END_FIGHT for itself (Main: player =
	# local player), so the half being ended must be the sender's own — the
	# waiting player's button must not end the OPPONENT's pile-in /
	# consolidation half (the scoped END_PILE_IN / END_CONSOLIDATION refuse
	# that too). Hot-seat / AI keep the unscoped behaviour.
	var half_scoped: bool = action.has("player") and _end_fight_half_is_scoped()
	if pile_in_step_11e == PileInStep11e.ACTIVE:
		if half_scoped and int(action.player) != piling_in_player_11e:
			return {"valid": false, "errors": ["Not your half of the Pile In step — Player %d is piling in (12.02)" % piling_in_player_11e]}
		return {"valid": true, "errors": []}
	if consolidation_step_11e == ConsolidationStep11e.ACTIVE:
		# 12.08 AFTER MOVING: "your opponent MUST select each of those units".
		if _forced_fights_pending_11e():
			return {"valid": false, "errors": ["Fights forced by an Engaging Consolidation must be resolved first (12.08)"]}
		if half_scoped and int(action.player) != consolidating_player_11e:
			return {"valid": false, "errors": ["Not your half of the Consolidate step — Player %d is consolidating (12.07)" % consolidating_player_11e]}
		return {"valid": true, "errors": []}
	if consolidation_step_11e == ConsolidationStep11e.DONE or sequencer_11e == null:
		return {"valid": true, "errors": []}
	if pile_in_step_11e == PileInStep11e.NOT_STARTED:
		return {"valid": false, "errors": ["Resolve the start-of-phase choices first — the Pile In step (12.02) has not begun"]}

	# The Fight step (12.04): "Players resolve the following sequence until
	# all eligible units have been selected to fight and their attacks have
	# been resolved." Ending it early is not a player choice.
	if active_fighter_id != "":
		return {"valid": false, "errors": ["%s is still fighting — finish its fight first (12.04)" % _fight_attached_display_name(active_fighter_id)]}
	var status = get_end_fight_status()
	if status.step_over:
		return {"valid": true, "errors": []}
	var player := int(action.get("player", status.selecting_player))
	if player != int(status.selecting_player):
		return {"valid": false, "errors": ["Player %d must select a unit to fight next — the Fight step cannot end while eligible units remain (12.04)" % status.selecting_player]}
	if status.can_pass:
		return {"valid": true, "errors": []}
	var names: Array = []
	for entry in status.owed_units:
		names.append(entry.unit_name)
	return {"valid": false, "errors": [
		"Every eligible unit must fight (12.04). Still to fight: %s. You may only pass when all of your eligible units are more than 5\" from every enemy unit." % ", ".join(names)]}

## The one authority the UI, AI and validator share for "can the Fight step
## (12.04) end, or can the selecting player pass (p.74)?". Returns:
##   step_over        — nobody is left to select (END_FIGHT moves on)
##   selecting_player — who selects next (0 when step_over)
##   can_pass         — selecting player may pass: all of their eligible
##                      units are more than 5" from every enemy unit
##   owed_units       — the selecting player's units that must still fight
## Diffs stamping FightSequencer.FIGHT_DONE_FLAG (this turn's key) on the
## Attached unit headed by unit_id (or just unit_id with group=false) — the
## synced "this unit's fight is over this turn" record a multiplayer client's
## sequencer reads.
func _fight_done_changes_11e(unit_id: String, group: bool = true) -> Array:
	var key := FightSequencer.turn_key(GameState.state)
	var ids: Array = _fight_group_ids(unit_id) if group else [unit_id]
	var out: Array = []
	for member_id in ids:
		out.append({"op": "set", "path": "units.%s.flags.%s" % [member_id, FightSequencer.FIGHT_DONE_FLAG], "value": key})
	return out

func get_end_fight_status() -> Dictionary:
	var status := {"step_over": true, "selecting_player": 0, "can_pass": false, "owed_units": []}
	if sequencer_11e == null or pile_in_step_11e == PileInStep11e.ACTIVE \
			or consolidation_step_11e != ConsolidationStep11e.NOT_STARTED:
		return status
	# Before the global Pile In step has started (a start-of-phase choice is
	# still pending) the Fight step has not
	# begun: nothing can end, and nobody can pass yet.
	if pile_in_step_11e == PileInStep11e.NOT_STARTED:
		return {"step_over": false, "selecting_player": 0, "can_pass": false, "owed_units": [], "pre_pile_in": true}
	var sel = sequencer_11e.peek_selection(GameState.state)
	if sel.done:
		return status
	status.step_over = false
	status.selecting_player = int(sel.player)
	status.can_pass = sequencer_11e.can_pass(GameState.state, int(sel.player))
	status.owed_units = get_unfought_eligible_units(int(sel.player))
	return status

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
		return _end_fight_log(_advance_pile_in_step_11e(create_result(true, [])), "Finished Pile In (12.02)")
	if consolidation_step_11e == ConsolidationStep11e.NOT_STARTED:
		# The validator only lets END_FIGHT through in the Fight step when the
		# step is over, or as the selecting player's PASS (p.74 "Eligible to
		# fight, but unable to fight" — all of their eligible units are more
		# than 5" from every enemy unit). A pass is not a forfeit: the
		# sequence returns to the opponent, and the passing player's units are
		# offered again once the opponent selects a unit. The Fight step ends
		# if both players pass in succession, or the opponent has nothing left
		# to select.
		var status = get_end_fight_status()
		if sequencer_11e != null and not status.step_over:
			var passing_player := int(action.get("player", status.selecting_player))
			var step_ends: bool = sequencer_11e.pass_selection(GameState.state, passing_player)
			log_phase_message("[11e p.74] Player %d passes — every eligible unit is more than 5\" from all enemy units%s" % [
				passing_player, " — the Fight step ends" if step_ends else ""])
			var pass_text := "Passed: every eligible unit is more than 5\" from all enemy units (p.74)"
			if not step_ends:
				return _end_fight_log(_resume_fight_step_after_end_11e(create_result(true, [])), pass_text)
			return _end_fight_log(_begin_consolidation_step_11e(), pass_text)
		return _end_fight_log(_begin_consolidation_step_11e(), "Ended the Fight step (12.04)")
	if consolidation_step_11e == ConsolidationStep11e.ACTIVE:
		# (12.08 forced fights can't be skipped — the validator rejects
		# END_FIGHT while any are pending.)
		consolidation_done_players_11e[consolidating_player_11e] = true
		log_phase_message("[11e 12.07] Player %d ends their consolidation half via END_FIGHT" % consolidating_player_11e)
		return _end_fight_log(_advance_consolidation_step_11e(create_result(true, [])), "Finished Consolidation (12.07)")

	return _run_end_of_fight_triggers(create_result(true, []))

# END_FIGHT ends whichever Fight-phase step is running (or is a p.74 pass);
# give the game log that outcome instead of a blanket "Ended Fight Phase"
# (BasePhase copies result.log_text onto the action for GameEventLog).
func _end_fight_log(result: Dictionary, text: String) -> Dictionary:
	if result.get("success", false) and str(result.get("log_text", "")) == "":
		result["log_text"] = text
	return result

# After the selecting player passes (p.74), hand the Fight step over to the
# opponent (12.04) and emit the next fight-selection request. Mirrors
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
	# Codex: Orks (11e) Fight On Death: models still kept on the battlefield
	# are removed at the end of the phase ("whichever comes first"). Applied
	# and kill-processed NOW so the end-of-phase window, objective control and
	# Deadly Demise see the board without them; the diffs also ride the result
	# (replay / network — _check_kill_diffs processes a destruction once).
	var fod_end_diffs = _ork11e_fod_remove_all("the end of the Fight phase")
	if not fod_end_diffs.is_empty():
		PhaseManager.apply_state_changes(fod_end_diffs)
		_check_kill_diffs(fod_end_diffs)
		var fod_changes: Array = result.get("changes", [])
		fod_changes.append_array(fod_end_diffs)
		result["changes"] = fod_changes

	# STRATAGEM WINDOW fight_phase_end (design §3): "end of the Fight phase,
	# before it actually ends" — active player first, then the non-active one
	# (KEEP IT RUNNIN' either turn, INSTINCTIVE HUNTERS opponent's turn). Opens
	# once; the resume re-enters here for the remaining end-of-phase triggers.
	if not _fight_phase_end_window_opened:
		_fight_phase_end_window_opened = true
		var fpe_paused := open_stratagem_window_both_players("fight_phase_end", {"phase": "fight"}, "_resume_after_fight_phase_end_window")
		var fpe_diffs: Array = consume_window_diffs()
		if not fpe_diffs.is_empty():
			var fpe_changes: Array = result.get("changes", [])
			fpe_changes.append_array(fpe_diffs)
			result["changes"] = fpe_changes
		if fpe_paused:
			log_phase_message("Waiting for a fight_phase_end stratagem decision before the Fight phase ends")
			return result

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

## Resume point for the fight_phase_end window(s): carry on with the rest of
## the end-of-phase triggers (Sweeping Advance, Acrobatic Escape, completion).
func _resume_after_fight_phase_end_window(_ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	return _run_end_of_fight_triggers(create_result(true, []))

## Follow-ups returned by FIGHT-group stratagems (design §3.2):
##   embark {unit_id, transport_id}  — KEEP IT RUNNIN'
##   strategic_reserves {unit_id}    — INSTINCTIVE HUNTERS
## Both resolve immediately (no player interaction): the diffs are applied now
## and handed to the window flow (_window_sync_diffs, merged into the result of
## the action that answered the window — human USE or the AI's synchronous use).
func _execute_window_followup(player: int, window_id: String, followup: Dictionary, ctx: Dictionary) -> bool:
	var diffs: Array = []
	match str(followup.get("type", "")):
		"embark":
			# source: the stratagem's name for the log (KEEP IT RUNNIN'; Codex: Space Marines DUTY IS NEVER DONE).
			_ork11e_embark_source = str(followup.get("source", "KEEP IT RUNNIN'"))
			diffs = _ork11e_embark_followup_diffs(str(followup.get("unit_id", "")), str(followup.get("transport_id", "")))
		# Codex: Space Marines (11e) WIND-SWIFT EVASION (SMCodex11e.gd): a normal / fall-back move at the end of the phase.
		"sm11e_fight_move":
			return _sm11e_movement().fight_move_start(self, player, followup)
		"strategic_reserves":
			# source: the stratagem's name for the log (INSTINCTIVE HUNTERS; Space Wolves CO-ORDINATED STRIKE).
			diffs = _ork11e_strategic_reserves_followup_diffs(str(followup.get("unit_id", "")), str(followup.get("source", "INSTINCTIVE HUNTERS")))
		_:
			return super._execute_window_followup(player, window_id, followup, ctx)
	if not diffs.is_empty():
		PhaseManager.apply_state_changes(diffs)
		_window_sync_diffs.append_array(diffs)
	return false

## 18.02 embark, same diffs as MovementPhase._process_embark_unit: the unit and
## every CHARACTER attached to it board together and leave the battlefield.
## TransportManager.can_embark (capacity, keywords, not set up this turn) is
## re-checked at resolution.
var _ork11e_embark_source := "KEEP IT RUNNIN'"  # the stratagem named by the embark follow-up's log line

func _ork11e_embark_followup_diffs(unit_id: String, transport_id: String) -> Array:
	var check: Dictionary = TransportManager.can_embark(unit_id, transport_id)
	if not check.get("valid", false):
		_window_error("embark follow-up: %s cannot embark within %s — %s" % [unit_id, transport_id, str(check.get("reason", "?"))])
		return []
	var transport = get_unit(transport_id)
	var embarked: Array = transport.get("transport_data", {}).get("embarked_units", []).duplicate()
	var diffs: Array = []
	for gid in TransportManager.get_attached_unit_group(unit_id, GameState.state):
		diffs.append({"op": "set", "path": "units.%s.embarked_in" % gid, "value": transport_id})
		# 18.04 / 18.06 "did not embark within that TRANSPORT this phase" —
		# same marker as MovementPhase._process_embark_unit (PhaseManager clears it).
		diffs.append({"op": "set", "path": "units.%s.flags.embarked_this_phase" % gid, "value": true})
		if not gid in embarked:
			embarked.append(gid)
		var g_models = get_unit(gid).get("models", [])
		for i in range(g_models.size()):
			diffs.append({"op": "set", "path": "units.%s.models.%d.position" % [gid, i], "value": null})
	diffs.append({"op": "set", "path": "units.%s.transport_data.embarked_units" % transport_id, "value": embarked})
	var msg := "%s: %s embarks within %s" % [str(_ork11e_embark_source), get_unit(unit_id).get("meta", {}).get("name", unit_id),
		transport.get("meta", {}).get("name", transport_id)]
	log_phase_message(msg)
	var gel = get_node_or_null("/root/GameEventLog")
	if gel:
		gel.add_combat_result("  " + msg)
	return diffs

## 20.02 repositioned unit: removed from the battlefield into strategic
## reserves (the existing reserves path: status IN_RESERVES +
## reserve_type strategic_reserves — EVASIVE MANOOVA / DED SNEAKY pattern), the
## whole Attached unit together. `repositioned_to_reserves` exempts it from the
## end-of-round-3 destruction of reserves (20.04 exception).
func _ork11e_strategic_reserves_followup_diffs(unit_id: String, source: String = "INSTINCTIVE HUNTERS") -> Array:
	var u = get_unit(unit_id)
	if u.is_empty():
		_window_error("strategic_reserves follow-up: unknown unit %s" % unit_id)
		return []
	var diffs: Array = []
	for gid in TransportManager.get_attached_unit_group(unit_id, GameState.state):
		diffs.append({"op": "set", "path": "units.%s.status" % gid, "value": GameStateData.UnitStatus.IN_RESERVES})
		diffs.append({"op": "set", "path": "units.%s.reserve_type" % gid, "value": "strategic_reserves"})
		diffs.append({"op": "set", "path": "units.%s.flags.repositioned_to_reserves" % gid, "value": true})
		# The unit leaves the battlefield: wipe every model's position (as the
		# KEEP IT RUNNIN' embark follow-up and the INFESTED WAR ZONE clone do).
		# Targeting, engagement, objective control and collision read model
		# positions, not the IN_RESERVES status, so a positioned reserve unit
		# stayed on the table as an invisible ghost until it arrived.
		var g_models = get_unit(gid).get("models", [])
		for i in range(g_models.size()):
			diffs.append({"op": "set", "path": "units.%s.models.%d.position" % [gid, i], "value": null})
	var msg := "%s: %s is placed in strategic reserves" % [source, u.get("meta", {}).get("name", unit_id)]
	log_phase_message(msg)
	var gel = get_node_or_null("/root/GameEventLog")
	if gel:
		gel.add_combat_result("  " + msg)
	return diffs

# ============================================================================
# SWEEPING ADVANCE
# ============================================================================

func _get_sweeping_advance_eligible_units() -> Array:
	"""Find units with the Sweeping Advance ability that were eligible to fight this phase and haven't used it yet."""
	var eligible = []
	var all_units = game_state_snapshot.get("units", {})
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")

	# Codex: Adeptus Custodes (11e): "if this unit was ELIGIBLE TO FIGHT this
	# phase" — not only the units that fought (CustodesAbilities.gd, WP-C7).
	for unit_id in _cus11e_abilities().sweeping_advance_candidates(units_that_fought):
		var unit = all_units.get(unit_id, {})
		if unit.is_empty():
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
		# `ap` is stored negative (AP-1 == -1), so "(AP -%d)" printed "AP --1"
		# once the 11e path started reaching this line. Normalise to one "-N"
		# reading regardless of the caller's sign convention.
		var ap_mag = absi(int(ap))
		save_type = "Armour Save %s (AP %s)" % [threshold, ("0" if ap_mag == 0 else "-%d" % ap_mag)]

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

func _fight_effective_move_cap(unit: Dictionary, model: Dictionary, rotations: Dictionary, key, base_cap: float = 3.0) -> float:
	# The positional distance a model may move: 3" minus the pivot cost if the
	# action pivots it (new facing differs from its current stored facing).
	# Codex: Adeptus Custodes (11e) — Unstoppable Destroyer (4") and Dread
	# Host Favoured Dacatarai (-2" for an enemy engaged with that unit) change
	# the base (CustodesDetachments.fight_move_cap, WP-C46); base_cap is the
	# step's base (3", or LIGHTNING WRATH's D3+3" pile-in — WP-C5).
	var cap: float = _fight_base_move_cap(str(unit.get("id", "")), base_cap)
	var new_rot = _fight_rotation_for_key(rotations, key)
	if new_rot != null:
		var old_rot = float(model.get("rotation", 0.0))
		if abs(float(new_rot) - old_rot) > 0.001:
			cap -= _fight_pivot_cost_for_model(unit, model)
	return max(0.0, cap)

## The pile-in / consolidation base distance before pivot costs: 3", or the
## Codex: Adeptus Custodes (11e) adjusted cap (WP-C46).
func _fight_base_move_cap(unit_id: String, base: float = 3.0) -> float:
	if unit_id == "" or GameConstants.edition < 11:
		return base
	return float(_cus11e_det().fight_move_cap(unit_id, base))

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
		# Codex: Adeptus Custodes LIGHTNING WRATH (CustodesCodex11e.gd): a D3+3" pile-in move.
		var pile_base_cap := maxf(3.0, float(_cus11e_codex().pile_in_inches(unit_id))) if pile_in_step_11e == PileInStep11e.ACTIVE else 3.0
		var cap = _fight_effective_move_cap(get_unit(route.unit_id), move_model, rotations, key, pile_base_cap)
		if dist > cap + MOVEMENT_CAP_EPSILON:
			if cap < _fight_base_move_cap(route.unit_id, pile_base_cap):
				errors.append("Model %s pile in exceeds %.0f\" limit after pivot cost (%.1f\")" % [str(key), cap, dist])
			elif cap != 3.0:
				errors.append("Model %s pile in exceeds %.0f\" limit (%.1f\")" % [str(key), cap, dist])
			else:
				errors.append("Model %s pile in exceeds %.0f\" limit (%.1f\")" % [str(key), pile_base_cap, dist])
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
	# Codex: Adeptus Custodes (11e) Unstoppable Destroyer: a free mode choice
	# (action.chosen_mode) among the applicable modes (WP-C46).
	var sel = tmpl.select_mode(unit_id, folded_board, {"chosen_mode": str(action.get("chosen_mode", ""))})
	var mode = str(sel.mode)
	# Per-model consolidation is optional (FAQ): an empty payload completes
	# the mandatory step without moving. Only validate geometry when models
	# actually move.
	if movements.is_empty():
		return {"valid": true, "errors": []}
	if mode == "":
		return {"valid": false, "errors": ["no consolidation mode applies — the unit cannot move (12.08)"]}
	# 12.08 BEFORE (Objective mode): the player selects ONE of the objectives
	# within 3". The pick rides on the action so the geometry validated here is
	# the geometry the dialog offered; an absent pick defaults to the closest.
	var chosen_objective = str(action.get("chosen_objective", ""))
	var ctx = tmpl.before_moving(unit_id, folded_board, null,
		{"mode": mode, "chosen_objective": chosen_objective})
	if ctx.has("error"):
		return {"valid": false, "errors": [ctx.error]}
	if mode == "objective" and chosen_objective != "" and chosen_objective != str(ctx.get("objective", "")):
		return {"valid": false, "errors": ["%s is not within 3\" of %s — select one of: %s (12.08)" % [
			consolidation_objective_label_11e(chosen_objective), unit_id,
			str(ctx.get("objective_candidates", []))]]}
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
			if cap < _fight_base_move_cap(route.unit_id):
				errors.append("Model %s consolidation exceeds %.0f\" limit after pivot cost (%.1f\")" % [str(key), cap, dist])
			elif cap != 3.0:
				errors.append("Model %s consolidation exceeds %.0f\" limit (%.1f\")" % [str(key), cap, dist])
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

# ============================================================================
# 12.08 CONSOLIDATION MODE — the single source the UI reads
# ============================================================================
#
# The Consolidate step's mode is MANDATORY and assessed in a fixed order:
# Ongoing (engaged) -> Engaging (enemy unit within 3") -> Objective (objective
# within 3"). _validate_consolidate_11e resolves it through the
# ConsolidationMove template; the player-facing UI used to re-derive it from
# _can_unit_reach_engagement_range() — a 10e-era "could this unit reach
# engagement range with its 3\" move?" heuristic (3" move + 2" engagement range
# = 5"). The two disagree for any unit 3-5" from an enemy: 12.08 says Objective,
# the heuristic said engagement, so ConsolidateDialog printed the enemy rules and
# FightController reverted every drag toward the objective the right-hand picker
# had just offered ("[Objective]"). These helpers hand the UI the same context
# and the same per-model verdict the validator uses, so the two cannot drift
# apart again.

# 12.08 BEFORE MOVING for `unit_id`, resolved on the folded (19.03) board so an
# Attached unit is judged as the one unit it is. Returns
# ConsolidationMove.before_moving()'s dict plus "mode" ("" when no mode applies)
# and, in Objective mode, "objective_position" (board px) for the UI to draw its
# arrows toward and "objective_options" (every selectable objective, closest
# first) for the dialog's "Consolidate toward:" picker. `chosen_objective` is
# the player's pick from that picker — 12.08 BEFORE lets them select any
# objective the unit is within 3" of; an empty pick means "the closest".
func get_consolidation_context_11e(unit_id: String, chosen_objective: String = "", chosen_mode: String = "") -> Dictionary:
	var empty := {"mode": "", "targets": [], "objective": "", "objective_options": []}
	var tmpl: ConsolidationMove = MoveTypes.get_type("consolidation")
	if tmpl == null or get_unit(unit_id).is_empty():
		return empty
	var folded_board = _fight_folded_board(unit_id, GameState.state)
	# Unstoppable Destroyer (Codex: Adeptus Custodes 11e, WP-C46): when the
	# mandatory order is lifted, `available_modes` lists the choices and
	# `chosen_mode` picks one.
	var sel_ctx = tmpl.select_mode(unit_id, folded_board, {"chosen_mode": chosen_mode})
	var mode = str(sel_ctx.mode)
	if mode == "":
		return empty
	# 12.08 BEFORE: Objective mode is "select ONE of those objectives" — pass the
	# player's pick through; an empty pick defaults to the CLOSEST one.
	var ctx = tmpl.before_moving(unit_id, folded_board, null,
		{"mode": mode, "chosen_objective": chosen_objective})
	ctx["mode"] = mode
	if str(sel_ctx.get("free_choice_source", "")) != "":
		ctx["available_modes"] = sel_ctx.get("available", [mode])
		ctx["free_choice_source"] = str(sel_ctx.free_choice_source)
	if mode == "objective":
		ctx["objective_position"] = consolidation_objective_position_11e(str(ctx.get("objective", "")))
		ctx["objective_options"] = consolidation_objective_options_11e(ctx)
	log_phase_message("[11e 12.08] Consolidation mode for %s: %s%s" % [
		unit_id, mode,
		(" (objective %s of %s)" % [str(ctx.get("objective", "")), str(ctx.get("objective_candidates", []))]) if mode == "objective" else ""
	])
	return ctx

# The objectives this unit may select for its Objective Consolidation (12.08
# BEFORE), closest first, in the shape the UI picker needs: id, the board's own
# label for the marker ("CENTER", "NML 1" — the same text ObjectiveVisual prints
# next to it), its board-px centre, and how far the unit is from it.
func consolidation_objective_options_11e(ctx: Dictionary) -> Array:
	var out: Array = []
	for entry in ctx.get("objective_distances_px", []):
		var obj_id = str(entry.get("id", ""))
		out.append({
			"id": obj_id,
			"label": consolidation_objective_label_11e(obj_id),
			"position": consolidation_objective_position_11e(obj_id),
			"distance_inches": Measurement.px_to_inches(float(entry.get("distance_px", 0.0)))
		})
	return out

# Player-facing name for an objective marker. Mirrors ObjectiveVisual's own
# label derivation ("obj_nml_1" -> "NML 1") so the consolidation picker names
# the marker exactly as the board does.
func consolidation_objective_label_11e(obj_id: String) -> String:
	if obj_id == "":
		return ""
	return obj_id.replace("obj_", "").to_upper().replace("_", " ")

# Board-px centre of objective marker `obj_id`, or Vector2.ZERO when unknown.
# Objective positions round-trip through saves as {x, y} dicts, so accept both.
func consolidation_objective_position_11e(obj_id: String) -> Vector2:
	if obj_id == "":
		return Vector2.ZERO
	for obj in GameState.state.get("board", {}).get("objectives", []):
		if str(obj.get("id", "")) != obj_id:
			continue
		var pos = obj.get("position", Vector2.ZERO)
		if pos is Dictionary:
			return Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))
		if pos is Vector2:
			return pos
		return Vector2.ZERO
	return Vector2.ZERO

# 12.08 WHILE MOVING for ONE model — the same ConsolidationMove verdict
# _validate_consolidate_11e applies per moved model, so a drag the board accepts
# is a drag Confirm Move will accept. `key` is a fight-move key: a plain model
# index/id, or "char_unit:key" for an attached character's model (19.03).
# `ctx` comes from get_consolidation_context_11e().
func check_consolidation_model_move_11e(unit_id: String, key, new_pos: Vector2, ctx: Dictionary) -> Dictionary:
	var tmpl: ConsolidationMove = MoveTypes.get_type("consolidation")
	if tmpl == null:
		return {"allowed": true, "reason": ""}
	if str(ctx.get("mode", "")) == "":
		return {"allowed": false, "reason": "no consolidation mode applies — the unit cannot move (12.08)"}
	var route = _fight_split_move_key(unit_id, key)
	var model = _resolve_fight_model(route.unit_id, route.model_key)
	if model.is_empty():
		return {"allowed": true, "reason": ""}
	return tmpl.model_move_allowed(unit_id, model, {"x": new_pos.x, "y": new_pos.y}, GameState.state, ctx)
