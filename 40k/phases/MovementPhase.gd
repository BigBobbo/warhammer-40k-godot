extends BasePhase
class_name MovementPhase

const BasePhase = preload("res://phases/BasePhase.gd")


# MovementPhase - Full implementation of the Movement phase following 10e rules
# Supports: Normal Move, Advance, Fall Back, Remain Stationary, Surge Move

signal unit_move_begun(unit_id: String, mode: String)
signal model_drop_preview(unit_id: String, model_id: String, path_px: Array, inches_used: float, legal: bool)
signal model_drop_committed(unit_id: String, model_id: String, dest_px: Vector2, rotation: float)
signal unit_move_confirmed(unit_id: String, result_summary: Dictionary)
signal unit_move_reset(unit_id: String)
signal movement_mode_locked(unit_id: String, mode: String)
signal command_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary)
signal command_reroll_completed(original_rolls: Array, new_rolls: Array, context: String)  # P3-118: For reroll visualization
signal overwatch_opportunity(moved_unit_id: String, defending_player: int, eligible_units: Array)
signal overwatch_result(shooter_unit_id: String, target_unit_id: String, result: Dictionary)
signal fire_overwatch_opportunity(player: int, eligible_units: Array, enemy_unit_id: String)
signal rapid_ingress_opportunity(player: int, eligible_units: Array)
signal surge_move_completed(unit_id: String, distance_moved: float)
signal krump_and_run_opportunity(player: int, eligible_units: Array, fell_back_unit_id: String)
signal scatter_opportunity(player: int, eligible_units: Array, trigger_unit_id: String)
# 11e FIRE OVERWATCH (15.08) snap shot: the DEFENDING player allocates its
# wounds (05.03) — MovementController shows the allocation-group overlay and
# answers with APPLY_SAVES (one action per save batch).
signal saves_required(save_data_list: Array)
# Codex: Orks (11e) READIED BRAWLERS follow-up: ask the (human) owner to make an
# assault disembark move with `unit_id` from `transport_id` (MovementController
# shows the disembark dialog / placement; SKIP_ASSAULT_DISEMBARK declines it).
signal ork11e_assault_disembark_requested(player: int, transport_id: String, unit_id: String)
# T03: BEGIN_MODEL_DRAG passed validation — MovementController picks the model up
# (ghost + budget-coloured drag ruler) exactly as a mouse press on it would.
# source_unit_id is the unit that owns the model (an attached CHARACTER's own
# unit, otherwise unit_id).
signal model_drag_requested(unit_id: String, model_id: String, source_unit_id: String)

# Codex: Orks (11e) movement-group stratagem handlers (consumer helpers) + dispatcher.
const Ork11eMovement = preload("res://scripts/stratagems/ork_codex/OrkCodexMovement.gd")
const Ork11eCodex = preload("res://scripts/stratagems/ork_codex/OrkCodex11e.gd")
# WP-O6: Codex: Orks (11e) datasheet abilities (move / advance modifiers, triggers).
const OrkAbilities11eScript = preload("res://scripts/codex/orks/OrkAbilities11e.gd")
# Codex: Orks (11e) army rules + detachment rules (WP-O34).
const Ork11eArmyRules = preload("res://scripts/codex/orks/OrkArmyRules11e.gd")
const Ork11eDetachments = preload("res://scripts/codex/orks/OrkDetachments11e.gd")

# ISS-002: engagement range comes from GameConstants.engagement_range_inches()
# (edition-dependent). Do not re-declare it as a local constant.
const MOVEMENT_CAP_EPSILON: float = 0.02  # Floating-point tolerance for movement cap checks (< 1px)
# Bases at the touching boundary (W40K base-to-base contact) should not be flagged as
# overlapping. Strict `<` comparison in shape collision combined with mm→px rounding
# (e.g. 32mm → 50.39px diameter at 50px spacing) produces sub-pixel false-positives,
# which surface as phantom rejections when staging adjacent models in formation.
const OVERLAP_TOLERANCE_PX: float = 0.5

# Movement state tracking
var active_moves: Dictionary = {}
# 11e 18.04: unit_id -> bool, set when the DisembarkDialog's Combat Disembark
# toggle was checked (phase-owned dialog path); consumed when the resulting
# CONFIRM_DISEMBARK payload is built. Mirrors MovementController.
var _pending_combat_disembark: Dictionary = {}
# ISS-061: take-to-the-skies declarations awaiting the advance roll.
var _pending_take_to_skies: Dictionary = {}  # unit_id -> move_data
# ISS-073 (24.35): Super-Heavy Walker MOBILE-grant declarations awaiting the advance roll.
var _pending_shw_mobile: Dictionary = {}  # unit_id -> bool
# Turbo Boostas (Speedwaaagh!): turbo declarations awaiting the advance resolution.
var _pending_turbo_boost: Dictionary = {}  # unit_id -> bool
var dice_log: Array = []
var _awaiting_reroll_decision: bool = false
var _reroll_pending_unit_id: String = ""
var _reroll_pending_data: Dictionary = {}  # Stores original roll info
var _awaiting_overwatch_decision: bool = false
var _overwatch_moved_unit_id: String = ""  # The unit that just moved (potential target)

# Fire Overwatch state tracking (T3-11)
var _awaiting_fire_overwatch: bool = false
var _fire_overwatch_player: int = 0           # Defending player being offered Overwatch
var _fire_overwatch_enemy_unit_id: String = "" # The enemy unit that triggered the opportunity
var _fire_overwatch_eligible_units: Array = [] # Units eligible for Overwatch

# Rapid Ingress state tracking (T4-7)
var _awaiting_rapid_ingress: bool = false
var _rapid_ingress_player: int = 0             # Non-active player being offered Rapid Ingress
var _rapid_ingress_eligible_units: Array = []  # Reserve units eligible for Rapid Ingress
var _rapid_ingress_unit_id: String = ""        # The unit chosen for Rapid Ingress placement

# P2-88: Rapid Ingress overwatch — if overwatch triggers after Rapid Ingress placement,
# we defer phase_completed until overwatch resolves
var _rapid_ingress_pending_phase_complete: bool = false

# 11e 15.09 SNAP SHOOTING (FIRE OVERWATCH 15.08) — AFTER SHOOTING: "Until the
# end of the phase, your unit is not eligible to start an action." Units whose
# cannot_start_action lock this phase set; it is lifted when the phase ends
# (the flag is otherwise only reset at the owner's next turn start).
var _snap_after_shooting_units: Array = []
# The snap shot in flight: shooter / target / defender, the wound batches the
# defender still allocates (05.03), and the dice + diffs gathered so far.
var _snap_saves: Dictionary = {}
# The save batch waiting for the defender (NetworkManager mirrors it here on
# the defending client, like ShootingPhase.pending_save_data).
var pending_save_data: Array = []

# Normal move tracking (P2-72) — 10e Core Rules
# "A unit cannot make more than one Normal move per phase."
# Tracks which units have made a Normal move this phase to enforce the limit.
var _normal_moves_this_phase: Dictionary = {}   # unit_id -> true (units that have Normal-moved this phase)

# Surge move tracking (P2-71) — 10e Core Rules Update
# Surge moves are out-of-phase moves triggered by abilities.
# Restrictions: once per phase per unit, not while battle-shocked, not while in Engagement Range.
var _surge_moves_this_phase: Dictionary = {}    # unit_id -> true (units that have surged this phase)

# Krump and Run state tracking (OA-8). The same scaffolding also serves
# ON TO DA NEXT (Taktikal Brigade) — an identical reactive 6" Normal move
# offered to the defending Ork player after an enemy unit Falls Back.
var _awaiting_krump_and_run: bool = false
var _krump_and_run_player: int = 0               # Non-active player offered the stratagem
var _krump_and_run_eligible_units: Array = []     # Eligible ORKS units freed by fall back
var _krump_and_run_fell_back_unit_id: String = "" # The enemy unit that fell back
var _krump_and_run_unit_id: String = ""           # The unit chosen for reactive move
var _krump_and_run_pending_after_overwatch: bool = false  # Defer K&R check until overwatch resolves
var _krump_and_run_pending_fell_back_id: String = ""      # Fell-back unit ID for deferred check
var _krump_and_run_strat_id: String = ""          # Resolved stratagem id (Krump and Run / On to da Next)
var _krump_and_run_strat_name: String = "Krump and Run"  # Display name for logs/dialog
var _engagement_at_phase_start: Dictionary = {}   # unit_id -> [enemy_unit_ids] at phase start
var _reactive_move_owner: int = 0                 # Override player for engagement checks during reactive moves

# Codex: Orks (11e) stratagem windows + follow-ups (design .llm/ork_codex_11e_design.md §3, §6)
var _ork11e_stm_opened: Dictionary = {}         # "unit_id:move_type" -> true: selected-to-move windows already opened this phase
var _ork11e_eem_pending: Dictionary = {}        # {unit_id, move_type}: an active-player move ended, enemy_ended_move not yet opened
var _ork11e_reactive_move: Dictionary = {}      # {player, unit_id, max_inches, source}: a HUMAN reactive normal move in progress
var _ork11e_auto_moving: bool = false           # an AI reactive normal move is being resolved synchronously
var _ork11e_assault_disembark: Dictionary = {}  # {player, transport_id, remaining}: READIED BRAWLERS follow-up in progress
var _ork11e_phase_end_windows_done: bool = false
var _ork11e_pending_move_changes: Array = []    # the ended move's diffs while its CONFIRM is still being processed (see _post_move_prompts)


# OA-42: Scatter! state tracking (Grot Tanks reactive move)
var _awaiting_scatter: bool = false
var _scatter_player: int = 0                        # Defending player offered Scatter!
var _scatter_eligible_units: Array = []             # Eligible units with Scatter! ability
var _scatter_trigger_unit_id: String = ""           # The enemy unit that triggered the opportunity
var _scatter_unit_id: String = ""                   # The unit chosen for reactive move
var _scatter_pending_after_overwatch: bool = false   # Defer Scatter! check until overwatch resolves
var _scatter_pending_trigger_id: String = ""         # Trigger unit ID for deferred check
var _scatter_pending_changes: Array = []             # Pending changes to propagate after Scatter!
var _scatter_pending_dice: Array = []                # Pending dice to propagate after Scatter!

# Calculate pivot value for a unit based on base type and keywords.
#
# 11e (the player edition): pivoting/rotating a model is FREE — the core rules
# state "rotating a model does not count towards the distance it has moved",
# with no exception for non-circular bases, Vehicles or Monsters. So every unit
# has a 0" pivot value at edition >= 11 and no movement is deducted for turning.
#
# The 2" pivot cost below is a 10e-only rule (Pariah Nexus Companion & Q3 2024
# Balance Update) — retained solely for the edition==10 regression baseline:
# - All non-round base models: 2" (Pariah Nexus expanded this from just Vehicle/Monster)
# - Vehicle round base >32mm with flying stem/hover stand: 2" (August 2024 FAQ)
# - Aircraft: 0"
# - All other (standard round base): 0"
func get_pivot_value_for_unit(unit_id: String) -> float:
	# 11e: no pivot cost for any base type — rotating is free.
	if GameConstants.edition >= 11:
		return 0.0

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return 0.0

	var keywords = unit.get("meta", {}).get("keywords", [])
	var is_vehicle = "VEHICLE" in keywords
	var is_aircraft = "AIRCRAFT" in keywords

	# Aircraft always have 0" pivot value
	if is_aircraft:
		return 0.0

	# Check base type from first alive model
	var base_type = "circular"
	var base_mm = 32
	var has_flying_stem = false
	var models = unit.get("models", [])
	for model in models:
		if model.get("alive", true):
			base_type = model.get("base_type", "circular")
			base_mm = model.get("base_mm", 32)
			has_flying_stem = model.get("flying_stem", false)
			break

	# Non-round base (rectangular, oval, etc.) — ALL non-round bases cost 2" per Pariah Nexus
	if base_type != "circular":
		return 2.0

	# Round base >32mm with flying stem — Vehicle only (August 2024 FAQ)
	if base_type == "circular" and base_mm > 32 and has_flying_stem and is_vehicle:
		return 2.0

	return 0.0

# Helper function to get unit movement stat with proper error handling
func get_unit_movement(unit: Dictionary) -> float:
	var movement: float = 6.0
	# Try the expected path first
	if unit.has("meta") and unit.meta.has("stats") and unit.meta.stats.has("move"):
		movement = float(unit.meta.stats.move)
	elif unit.get("meta", {}).get("stats", {}).has("move"):
		# Try nested get with type safety
		movement = float(unit.get("meta", {}).get("stats", {}).get("move"))
	else:
		# Log warning and return default
		var unit_name = unit.get("meta", {}).get("name", "Unknown")
		push_warning("Unit %s missing movement stat, using default: 6" % unit_name)

	# BIONIK WORKSHOP (OA-2): +1 Move bonus
	var bionik_bonus = unit.get("flags", {}).get("bionik_workshop_bonus", "")
	if bionik_bonus == "move":
		movement += 1.0
		DebugLogger.info(str("MovementPhase: Bionik Workshop — movement %d → %d (+1\")" % [int(movement - 1), int(movement)]))

	# FOLLOW ME LADZ (#394 / War Horde enhancement): +n" to Move characteristic
	# while bearer leads the unit. Set as effect_plus_move flag on the bearer's
	# unit by EffectPrimitives when the enhancement is applied.
	var plus_move = int(unit.get("flags", {}).get("effect_plus_move", 0))
	if plus_move > 0:
		var old_move = movement
		movement += float(plus_move)
		DebugLogger.info(str("MovementPhase: effect_plus_move — movement %d → %d (+%d\") for %s" % [int(old_move), int(movement), plus_move, unit.get("meta", {}).get("name", "?")]))

	# Codex: Orks (11e) FUNGUS-FUEL INJECTION: "+2\" M" until the end of the phase
	# (own flag, so it never clobbers an enhancement's effect_plus_move).
	var ffi_move = int(unit.get("flags", {}).get(Ork11eMovement.FLAG_PLUS_MOVE, 0))
	if ffi_move > 0:
		movement += float(ffi_move)
		DebugLogger.info(str("MovementPhase: FUNGUS-FUEL INJECTION — movement %d → %d (+%d\") for %s" % [int(movement - ffi_move), int(movement), ffi_move, unit.get("meta", {}).get("name", "?")]))

	# Codex: Adeptus Custodes (11e) Solar Watch — Favoured Ka'tah Calistus:
	# "+2\" M" while the unit uses Calistus (WP-C46).
	var cus11e_mv: float = float(_cus11e_det().move_bonus_inches(unit))
	if cus11e_mv > 0.0:
		movement += cus11e_mv
		DebugLogger.info(str("MovementPhase: Calistus (Solar Watch) — movement +%.0f\" for %s" % [cus11e_mv, unit.get("meta", {}).get("name", "?")]))
	# Codex: Space Marines (11e) Wolf-Touched (Saga of the Beastslayer): "+2\" M" for the bearer's unit (WP-S2).
	var sw11e_mv: float = float(load("res://scripts/codex/space_wolves/SWDetachments11e.gd").move_bonus_inches(unit)) if GameConstants.edition >= 11 else 0.0
	if sw11e_mv > 0.0:
		movement += sw11e_mv
		DebugLogger.info(str("MovementPhase: Wolf-Touched — movement +%.0f\" for %s" % [sw11e_mv, unit.get("meta", {}).get("name", "?")]))
	# WP-M2a Codex: Space Marines (11e) Lightning-fast Strike (Stormlance Task Force): AA MOUNTED / SPEEDER +2" M.
	var sm11e_mv: float = float(load("res://scripts/codex/space_marines/SMDetachmentsA.gd").move_bonus_inches(unit)) if GameConstants.edition >= 11 else 0.0
	if sm11e_mv > 0.0:
		movement += sm11e_mv
		DebugLogger.info(str("MovementPhase: Lightning-fast Strike — movement +%.0f\" for %s" % [sm11e_mv, unit.get("meta", {}).get("name", "?")]))
	# WP-O6: Codex: Orks (11e) datasheet abilities — Runnin' wiv da Herd (+4"),
	# Madcap Artillery 'smashed' (-2").
	if GameConstants.edition >= 11:
		var o6_move: float = OrkAbilities11eScript.move_modifier(unit) + float(_cus11e_abilities().move_modifier(unit))  # WP-C7: Seeker's Instincts +2"
		# Codex: Space Marines (11e) MIGHT OF THE MACHINE SPIRIT (SMCodex11e.gd): harmful M modifiers ignored.
		if o6_move < 0.0 and _sm11e_codex().ignores_move_penalties(unit):
			DebugLogger.info(str("MovementPhase: Might of the Machine Spirit — ignoring a %.0f\" M modifier for %s" % [o6_move, unit.get("meta", {}).get("name", "?")]))
			o6_move = 0.0
		if o6_move != 0.0:
			var pre_o6 = movement
			movement = maxf(0.0, movement + o6_move)
			DebugLogger.info(str("MovementPhase: [WP-O6] Ork datasheet move modifier %+.0f\" — movement %d → %d for %s" % [o6_move, int(pre_o6), int(movement), unit.get("meta", {}).get("name", "?")]))

	return movement

func _init():
	phase_type = GameStateData.Phase.MOVEMENT

func _on_phase_enter() -> void:
	log_phase_message("Entering Movement Phase")
	active_moves.clear()
	dice_log.clear()
	_awaiting_reroll_decision = false
	_reroll_pending_unit_id = ""
	_reroll_pending_data = {}
	_awaiting_overwatch_decision = false
	_overwatch_moved_unit_id = ""
	_awaiting_fire_overwatch = false
	_fire_overwatch_player = 0
	_fire_overwatch_enemy_unit_id = ""
	_fire_overwatch_eligible_units = []
	_awaiting_rapid_ingress = false
	_rapid_ingress_player = 0
	_rapid_ingress_eligible_units = []
	_rapid_ingress_unit_id = ""
	_snap_after_shooting_units = []
	_snap_saves = {}
	pending_save_data = []
	_normal_moves_this_phase.clear()
	_surge_moves_this_phase.clear()
	_awaiting_krump_and_run = false
	_krump_and_run_player = 0
	_krump_and_run_eligible_units = []
	_krump_and_run_fell_back_unit_id = ""
	_krump_and_run_unit_id = ""
	_krump_and_run_pending_after_overwatch = false
	_krump_and_run_pending_fell_back_id = ""
	_krump_and_run_strat_id = ""
	_krump_and_run_strat_name = "Krump and Run"
	_reactive_move_owner = 0
	_awaiting_scatter = false
	_scatter_player = 0
	_scatter_eligible_units = []
	_scatter_trigger_unit_id = ""
	_scatter_unit_id = ""
	_scatter_pending_after_overwatch = false
	_scatter_pending_trigger_id = ""
	_scatter_pending_changes = []
	_scatter_pending_dice = []
	_ork11e_stm_opened.clear()
	_ork11e_eem_pending = {}
	_ork11e_reactive_move = {}
	_ork11e_auto_moving = false
	_ork11e_assault_disembark = {}
	_ork11e_phase_end_windows_done = false
	_ork11e_pending_move_changes = []
	_cus11e_ingress_asked.clear()
	_cus11e_held_ingress_action = {}

	# OA-8: Snapshot engagement state at phase start for Krump and Run eligibility
	_engagement_at_phase_start = _compute_engagement_snapshot()
	if not _engagement_at_phase_start.is_empty():
		DebugLogger.info(str("MovementPhase: OA-8 engagement snapshot — %d units in engagement at phase start" % _engagement_at_phase_start.size()))

	# Connect to TransportManager to handle disembark completion
	if TransportManager and not TransportManager.disembark_completed.is_connected(_on_transport_manager_disembark_completed):
		TransportManager.disembark_completed.connect(_on_transport_manager_disembark_completed)

	# Movement phase continues with the current active player
	# Player switching only happens during scoring phase transitions

	# Apply unit ability eligibility effects (fall_back_and_charge, etc.)
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_movement_phase_start()

		# OA-42: Clear Scatter! per-unit tracking for new turn
		ability_mgr.clear_scatter_turn_tracking()

	# Refresh snapshot after ability effects mutated GameState flags
	# (e.g. effect_auto_advance_6 from Turbo-boost, advance_and_charge from
	# Martial Inspiration). Without this, get_unit() reads stale data.
	game_state_snapshot = GameState.create_snapshot()

	_initialize_movement()

	# (The 10e Thievin' Scavengers start-of-movement CP roll is gone: the
	# Codex: Orks (11e) ability secures objectives at the END of the Movement
	# phase — OrkAbilities11e.on_movement_phase_end, called from END_MOVEMENT.)

	# Codex: Orks (11e) movement_phase_start window (09.01 Start of Movement
	# Phase, after the phase-start bookkeeping above): active player first.
	_ork11e_open_movement_phase_start_windows()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Movement Phase")

	# Clear unit ability eligibility flags
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr:
		ability_mgr.on_movement_phase_end()

	# P3-106: Clear stratagem phase-scoped effects at end of Movement phase
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		strat_manager.on_phase_end(GameStateData.Phase.MOVEMENT)

	# Disconnect from TransportManager
	if TransportManager and TransportManager.disembark_completed.is_connected(_on_transport_manager_disembark_completed):
		TransportManager.disembark_completed.disconnect(_on_transport_manager_disembark_completed)
	# Clear any temporary movement data
	for unit_id in active_moves:
		_clear_unit_move_state(unit_id)


func _initialize_movement() -> void:
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)

	var can_move = false
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) == GameStateData.UnitStatus.DEPLOYED:
			can_move = true
			break
		# Embarked units can disembark even if status is incorrect
		if unit.get("embarked_in", null) != null:
			can_move = true
			break

	# Also check for reserve units that can be deployed (Turn 2+).
	# battle_round lives under meta in snapshots — the old top-level read
	# always returned 1, so an all-in-reserves army had its movement phase
	# auto-completed even in rounds where reinforcements could arrive.
	if not can_move and (GameState.get_battle_round() >= 2 or not _cus11e_lightning_descent_reserves(current_player).is_empty()):
		var reserves = GameState.get_reserves_for_player(current_player) if GameState.get_battle_round() >= 2 else _cus11e_lightning_descent_reserves(current_player)
		if reserves.size() > 0:
			can_move = true
			log_phase_message("No deployed units can move, but %d reserve units available for reinforcement" % reserves.size())

	if not can_move:
		log_phase_message("No units available for movement, completing phase")
		emit_signal("phase_completed")


func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	# Check base phase validation first (handles DEBUG_MOVE)
	var base_validation = super.validate_action(action)
	if not base_validation.get("valid", true):
		return base_validation

	# 11e FIRE OVERWATCH: while the defender allocates the snap shot's wounds
	# (05.03) only their APPLY_SAVES is accepted.
	if not _snap_saves.is_empty():
		if action_type == "APPLY_SAVES":
			return _validate_snap_apply_saves(action)
		if not action_type.begins_with("DEBUG_"):
			return {"valid": false, "errors": ["Waiting for Player %d to allocate the FIRE OVERWATCH wounds (05.03)" % int(_snap_saves.get("defender", 0))]}

	# Codex: Orks (11e): while a stratagem follow-up owns the phase (a human
	# reactive normal move, a READIED BRAWLERS assault disembark) only the
	# actions that complete it are accepted.
	var ork11e_gate := _ork11e_followup_gate(action)
	if not ork11e_gate.is_empty():
		return ork11e_gate

	match action_type:
		"BEGIN_NORMAL_MOVE":
			return _validate_begin_normal_move(action)
		"BEGIN_ADVANCE":
			return _validate_begin_advance(action)
		"BEGIN_FALL_BACK":
			return _validate_begin_fall_back(action)
		"SET_MODEL_DEST":
			return _validate_set_model_dest(action)
		"STAGE_MODEL_MOVE":
			return _validate_stage_model_move(action)
		"BEGIN_MODEL_DRAG":
			return _validate_begin_model_drag(action)
		"UNDO_LAST_MODEL_MOVE":
			return _validate_undo_last_model_move(action)
		"RESET_UNIT_MOVE":
			return _validate_reset_unit_move(action)
		"CONFIRM_UNIT_MOVE":
			return _validate_confirm_unit_move(action)
		"REMAIN_STATIONARY":
			return _validate_remain_stationary(action)
		"LOCK_MOVEMENT_MODE":
			return _validate_lock_movement_mode(action)
		"SET_TAKE_TO_SKIES":
			return _validate_set_take_to_skies(action)
		"SET_ADVANCE_BONUS":
			return _validate_set_advance_bonus(action)
		"END_MOVEMENT":
			return _validate_end_movement(action)
		"DISEMBARK_UNIT":
			return _validate_disembark_unit(action)
		"CONFIRM_DISEMBARK":
			return _validate_confirm_disembark(action)
		"EMBARK_UNIT":
			return _validate_embark_unit(action)
		"PLACE_REINFORCEMENT":
			return _validate_place_reinforcement(action)
		# Codex: Adeptus Custodes (CustodesCodex11e.gd): a reserve unit selected to make an ingress move.
		"CUS11E_SELECT_INGRESS_UNIT":
			return _cus11e_validate_select_ingress(action)
		"USE_STRATAGEM":
			return _validate_use_stratagem(action)
		"USE_COMMAND_REROLL":
			if not _awaiting_reroll_decision:
				return {"valid": false, "errors": ["Not awaiting a Command Re-roll decision"]}
			return {"valid": true}
		"DECLINE_COMMAND_REROLL":
			if not _awaiting_reroll_decision:
				return {"valid": false, "errors": ["Not awaiting a Command Re-roll decision"]}
			return {"valid": true}
		"USE_FIRE_OVERWATCH":
			return _validate_use_fire_overwatch(action)
		"DECLINE_FIRE_OVERWATCH":
			return _validate_decline_fire_overwatch(action)
		"USE_RAPID_INGRESS":
			return _validate_use_rapid_ingress(action)
		"DECLINE_RAPID_INGRESS":
			return _validate_decline_rapid_ingress(action)
		"PLACE_RAPID_INGRESS_REINFORCEMENT":
			return _validate_place_rapid_ingress_reinforcement(action)
		"USE_KRUMP_AND_RUN":
			return _validate_use_krump_and_run(action)
		"DECLINE_KRUMP_AND_RUN":
			if not _awaiting_krump_and_run:
				return {"valid": false, "errors": ["Not awaiting Krump and Run decision"]}
			return {"valid": true}
		"APPLY_PIVOT_COST":
			return _validate_apply_pivot_cost(action)
		"BEGIN_SURGE_MOVE":
			return _validate_begin_surge_move(action)
		"USE_SCATTER":
			return _validate_use_scatter(action)
		"DECLINE_SCATTER":
			if not _awaiting_scatter:
				return {"valid": false, "errors": ["Not awaiting Scatter! decision"]}
			return {"valid": true}
		"SKIP_ASSAULT_DISEMBARK":
			return _validate_skip_assault_disembark(action)
		"DEBUG_MOVE":
			# Already validated by base class
			return {"valid": true}
		"END_COMMAND":
			# Idempotent no-op: previous phase auto-advanced before END_COMMAND was dispatched.
			return {"valid": true}
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	match action_type:
		"BEGIN_NORMAL_MOVE":
			return _process_begin_normal_move(action)
		"BEGIN_ADVANCE":
			return _process_begin_advance(action)
		"BEGIN_FALL_BACK":
			return _process_begin_fall_back(action)
		"SET_MODEL_DEST":
			return _process_set_model_dest(action)
		"STAGE_MODEL_MOVE":
			return _process_stage_model_move(action)
		"BEGIN_MODEL_DRAG":
			return _process_begin_model_drag(action)
		"UNDO_LAST_MODEL_MOVE":
			return _process_undo_last_model_move(action)
		"RESET_UNIT_MOVE":
			return _process_reset_unit_move(action)
		"CONFIRM_UNIT_MOVE":
			return _process_confirm_unit_move(action)
		"REMAIN_STATIONARY":
			return _process_remain_stationary(action)
		"LOCK_MOVEMENT_MODE":
			return _process_lock_movement_mode(action)
		"SET_TAKE_TO_SKIES":
			return _process_set_take_to_skies(action)
		"SET_ADVANCE_BONUS":
			return _process_set_advance_bonus(action)
		"END_MOVEMENT":
			return _process_end_movement(action)
		"DISEMBARK_UNIT":
			return _process_disembark_unit(action)
		"CONFIRM_DISEMBARK":
			return _process_confirm_disembark(action)
		"EMBARK_UNIT":
			return _process_embark_unit(action)
		"PLACE_REINFORCEMENT":
			return _process_place_reinforcement(action)
		"CUS11E_SELECT_INGRESS_UNIT":
			return _cus11e_process_select_ingress(action)
		"USE_STRATAGEM":
			return _process_use_stratagem(action)
		"USE_COMMAND_REROLL":
			return _process_use_command_reroll(action)
		"DECLINE_COMMAND_REROLL":
			return _process_decline_command_reroll(action)
		"USE_FIRE_OVERWATCH":
			return _process_use_fire_overwatch(action)
		"DECLINE_FIRE_OVERWATCH":
			return _process_decline_fire_overwatch(action)
		"APPLY_SAVES":
			return _process_snap_apply_saves(action)
		"USE_RAPID_INGRESS":
			return _process_use_rapid_ingress(action)
		"DECLINE_RAPID_INGRESS":
			return _process_decline_rapid_ingress(action)
		"PLACE_RAPID_INGRESS_REINFORCEMENT":
			return _process_place_rapid_ingress_reinforcement(action)
		"USE_KRUMP_AND_RUN":
			return _process_use_krump_and_run(action)
		"DECLINE_KRUMP_AND_RUN":
			return _process_decline_krump_and_run(action)
		"APPLY_PIVOT_COST":
			return _process_apply_pivot_cost(action)
		"BEGIN_SURGE_MOVE":
			return _process_begin_surge_move(action)
		"USE_SCATTER":
			return _process_use_scatter(action)
		"DECLINE_SCATTER":
			return _process_decline_scatter(action)
		"SKIP_ASSAULT_DISEMBARK":
			return _process_skip_assault_disembark(action)
		"END_COMMAND":
			return create_result(true, [], "")
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

# Validation Methods

func _validate_begin_normal_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}

	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Check if unit is embarked - if so, trigger disembark flow instead
	if unit.get("embarked_in", null) != null:
		# This will be handled by showing disembark dialog
		return {"valid": false, "errors": ["Unit is embarked - must disembark first"], "show_disembark": true}

	# Check if unit is attached to a bodyguard - cannot move independently
	if unit.get("attached_to", null) != null:
		return {"valid": false, "errors": ["Attached character moves with its bodyguard unit"]}

	if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
		return {"valid": false, "errors": ["Unit is not deployed"]}

	# B7 (23.02): AIRCRAFT are only eligible to make ingress moves — not
	# normal/advance/fall-back moves.
	if GameConstants.edition >= 11 and GameState.unit_is_aircraft(unit_id):
		return {"valid": false, "errors": ["AIRCRAFT can only make ingress moves"]}

	# Check if unit has already moved
	if unit.get("flags", {}).get("moved", false):
		return {"valid": false, "errors": ["Unit has already moved this phase"]}

	# P2-72: Enforce one Normal move per phase limit
	# 10e Core Rules: "A unit cannot make more than one Normal move per phase."
	if _normal_moves_this_phase.has(unit_id):
		log_phase_message("Normal move denied for %s: already made a Normal move this phase" % unit_id)
		return {"valid": false, "errors": ["Unit has already made a Normal move this phase"]}

	# Check if unit cannot move due to disembarking restrictions
	if unit.get("flags", {}).get("cannot_move", false):
		return {"valid": false, "errors": ["Unit cannot move (disembarked from transport that moved)"]}

	# Check if unit is in engagement range (cannot use Normal Move if engaged)
	# ISS-040 step 2: at 11e the template (live state) is authoritative.
	if GameConstants.edition >= 11:
		var el_11e = MoveTypes.get_type("normal").eligible(unit_id, GameState.state)
		if not el_11e.eligible:
			return {"valid": false, "errors": el_11e.reasons}
	elif _is_unit_engaged(unit_id):
		return {"valid": false, "errors": ["Unit is engaged, must Fall Back instead"]}

	# Issue #339: Units that arrived from Strategic Reserves this turn cannot move further
	# Per 10e Core Rules, the arrival counts as the unit's move for that turn
	var arrived_turn = unit.get("arrived_from_reserves_turn", -1)
	if arrived_turn >= 0 and arrived_turn == GameState.get_battle_round():
		return {"valid": false, "errors": ["Unit arrived from reserves this turn and cannot move further"]}

	return {"valid": true, "errors": []}

func _validate_begin_advance(action: Dictionary) -> Dictionary:
	# Same validation as normal move, plus advance-specific checks
	var base_validation = _validate_begin_normal_move(action)
	if not base_validation.valid:
		return base_validation
	
	# No additional restrictions for advance at this stage
	return {"valid": true, "errors": []}

func _validate_begin_fall_back(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}
	
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}
	
	if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
		return {"valid": false, "errors": ["Unit is not deployed"]}

	# B7 (23.02): AIRCRAFT are only eligible to make ingress moves.
	if GameConstants.edition >= 11 and GameState.unit_is_aircraft(unit_id):
		return {"valid": false, "errors": ["AIRCRAFT can only make ingress moves"]}

	# Check if unit has already moved
	if unit.get("flags", {}).get("moved", false):
		return {"valid": false, "errors": ["Unit has already moved this phase"]}

	# Fall Back is only allowed if engaged
	# ISS-040 step 2: at 11e the 09.07 template (live state) is authoritative.
	if GameConstants.edition >= 11:
		var el_11e = MoveTypes.get_type("fall_back").eligible(unit_id, GameState.state)
		if not el_11e.eligible:
			return {"valid": false, "errors": el_11e.reasons}
	elif not _is_unit_engaged(unit_id):
		return {"valid": false, "errors": ["Unit is not engaged, use Normal Move instead"]}

	# Issue #339: Units that arrived from Strategic Reserves this turn cannot move further
	# (Theoretically unreachable since reserves arrive >9" from enemies, but added for robustness)
	var arrived_turn = unit.get("arrived_from_reserves_turn", -1)
	if arrived_turn >= 0 and arrived_turn == GameState.get_battle_round():
		return {"valid": false, "errors": ["Unit arrived from reserves this turn and cannot move further"]}

	return {"valid": true, "errors": []}

func _validate_set_model_dest(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var model_id = payload.get("model_id", "")
	var dest = payload.get("dest", [])
	
	if unit_id == "" or model_id == "" or dest.size() != 2:
		return {"valid": false, "errors": ["Missing required fields"]}
	
	# Check if unit has an active move
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["No active move for unit"]}
	
	var move_data = active_moves[unit_id]
	var dest_vec = Vector2(dest[0], dest[1])
	
	# Validate movement distance
	var model = _get_model_in_unit(unit_id, model_id)
	if model.is_empty():
		return {"valid": false, "errors": ["Model not found in unit"]}
	
	var current_pos = _get_model_position(model)
	if current_pos == null:
		return {"valid": false, "errors": ["Model has no current position"]}
	
	var distance_inches = Measurement.distance_inches(current_pos, dest_vec)

	# ISS-054 (11e 13.06): dense terrain blocks non-INFANTRY/BEASTS/
	# SWARM/MOBILE models when a crossed section is >2\" high (>4\" with
	# SUPER-HEAVY WALKER) — the 2D board cannot path the mandated
	# vertical traversal, so the segment is refused. Shape-aware: the
	# model is passed so the whole base is swept, not just its centre.
	var gate_54 = _check_dense_terrain_gate(unit_id, move_data, current_pos, dest_vec, model)
	if not gate_54.valid:
		return gate_54

	# Add terrain penalty (difficult ground only — no height penalty, units stay on ground floor)
	var terrain_penalty = _get_movement_terrain_penalty(current_pos, dest_vec, unit_id)
	var effective_distance = distance_inches + terrain_penalty
	if effective_distance > move_data.move_cap_inches + MOVEMENT_CAP_EPSILON:
		return {"valid": false, "errors": ["Move exceeds cap: %.1f\" > %.1f\"" % [effective_distance, move_data.move_cap_inches]]}

	# Check engagement range restrictions
	var er_check = _check_engagement_range_at_position(unit_id, model_id, dest_vec, move_data.mode)
	if not er_check.valid:
		return {"valid": false, "errors": er_check.errors}

	# 10e Rule: Normal Move and Advance cannot cross enemy model bases
	# FLY units are exempt — they can move over enemy models
	# Fall Back and Surge are also exempt
	if move_data.mode in ["NORMAL", "ADVANCE"] and not _unit_has_fly_keyword(unit_id) and not _o6_moves_through_models(unit_id, move_data):
		if _path_crosses_enemy_bases(current_pos, dest_vec, unit_id, model):
			log_phase_message("  FAILED: Path crosses enemy model base (Normal/Advance cannot move through enemies)")
			return {"valid": false, "errors": ["Cannot move through enemy models during Normal Move or Advance"]}

	# 10e Errata: Cannot move across MONSTER or VEHICLE models (friendly or enemy)
	# FLY units are exempt
	if not _unit_has_fly_keyword(unit_id) and not _o6_moves_through_models(unit_id, move_data):
		if _path_crosses_monster_vehicle_bases(current_pos, dest_vec, unit_id, model):
			log_phase_message("  FAILED: Path crosses friendly/enemy Monster/Vehicle model base")
			return {"valid": false, "errors": ["Cannot move through Monster or Vehicle models"]}

	# Check terrain collision
	if _position_intersects_terrain(dest_vec, model):
		return {"valid": false, "errors": ["Position intersects impassable terrain"]}

	# Check model overlap
	if _position_overlaps_other_models(unit_id, model_id, dest_vec, model):
		return {"valid": false, "errors": ["Cannot end move on top of another model"]}

	# Check wall overlap — no model may end its move overlapping a wall
	# (path-traversal honors per-keyword blocks_movement separately). Mirrors
	# the client-side gate in MovementController._end_model_drag; required
	# here so SET_MODEL_DEST actions dispatched without the drag UI
	# (multiplayer, tests, AI) still hit the same rule. Keywords make the
	# 11e solid-feature half of the check keyword-aware (infantry exempt).
	var _wall_test_model_smd = model.duplicate(true)
	_wall_test_model_smd["position"] = dest_vec
	if Measurement.model_overlaps_any_wall(_wall_test_model_smd, _terrain_rule_keywords(unit_id, move_data)):
		return {"valid": false, "errors": ["Cannot end move overlapping a wall"]}

	# Check board edge - no part of model base can extend beyond the battlefield
	if _position_outside_board_bounds(dest_vec, model):
		return {"valid": false, "errors": ["Model cannot be placed beyond the board edge"]}

	return {"valid": true, "errors": []}

func _validate_stage_model_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var model_id = payload.get("model_id", "")
	var dest = payload.get("dest", [])

	if unit_id == "" or model_id == "" or dest.size() != 2:
		return {"valid": false, "errors": ["Missing required fields"]}

	# Check if unit has an active move
	if not active_moves.has(unit_id):
		log_phase_message("ERROR: No active move for unit %s. Active moves: %s" % [unit_id, active_moves.keys()])
		return {"valid": false, "errors": ["No active move for unit"]}

	var move_data = active_moves[unit_id]
	var dest_vec = Vector2(dest[0], dest[1])

	# Get model's current position (may be staged position)
	# If model_source_unit_id is provided (attached character), look there first
	# to avoid model ID collisions (e.g. both units having "m1")
	var model_source_unit_id = payload.get("model_source_unit_id", "")
	var model = {}
	var model_actual_unit_id = unit_id
	if model_source_unit_id != "":
		model = _get_model_in_unit(model_source_unit_id, model_id)
		if not model.is_empty():
			model_actual_unit_id = model_source_unit_id
			DebugLogger.info(str("[MovementPhase] Found model %s in specified source unit %s" % [model_id, model_source_unit_id]))
	if model.is_empty():
		model = _get_model_in_unit(unit_id, model_id)
	if model.is_empty():
		var bodyguard = get_unit(unit_id)
		var attached_chars = bodyguard.get("attachment_data", {}).get("attached_characters", [])
		for char_id in attached_chars:
			model = _get_model_in_unit(char_id, model_id)
			if not model.is_empty():
				model_actual_unit_id = char_id
				DebugLogger.info(str("[MovementPhase] Found model %s in attached character unit %s" % [model_id, char_id]))
				break
	if model.is_empty():
		return {"valid": false, "errors": ["Model not found in unit"]}

	var model_key = "%s:%s" % [model_actual_unit_id, model_id]

	# Check staged position if model has one
	var current_pos = null
	for staged_move in move_data.staged_moves:
		if staged_move.model_id == model_id and staged_move.get("model_source_unit_id", unit_id) == model_actual_unit_id:
			current_pos = staged_move.dest
			break

	# If no staged position, use actual position
	if current_pos == null:
		current_pos = _get_model_position(model)
		if current_pos == null:
			return {"valid": false, "errors": ["Model has no current position"]}

	# Get the model's original position
	var original_pos = move_data.original_positions.get(model_key, current_pos)
	log_phase_message("DEBUG: Validating move for model %s" % model_id)
	log_phase_message("  Original pos: %s, Current pos: %s, Dest: %s" % [original_pos, current_pos, dest_vec])

	# ISS-054 (11e 13.06): the same dense-terrain path gate SET_MODEL_DEST
	# runs. STAGE_MODEL_MOVE is the action the drag UI and the AI actually
	# dispatch — without the gate here, vehicles/monsters walked straight
	# through 5"-tall ruin walls (the Stompa-on-walls bug).
	var gate_54_stage = _check_dense_terrain_gate(unit_id, move_data, current_pos, dest_vec, model)
	if not gate_54_stage.valid:
		log_phase_message("  FAILED: %s" % str(gate_54_stage.errors))
		return gate_54_stage

	# Calculate total distance from original position to destination
	var total_distance_for_model = Measurement.distance_inches(original_pos, dest_vec)
	# Add terrain penalty (difficult ground only — no height penalty, units stay on ground floor)
	var terrain_penalty = _get_movement_terrain_penalty(original_pos, dest_vec, unit_id)
	total_distance_for_model += terrain_penalty
	log_phase_message("  Distance calculation: %.2f inches (terrain penalty: %.2f\")" % [total_distance_for_model, terrain_penalty])

	# Account for pivot cost (10e Core Rules Update) — pivot value reduces effective move cap
	var effective_cap = move_data.move_cap_inches
	if move_data.get("pivot_cost_applied", false):
		effective_cap -= move_data.get("pivot_value", 0.0)

	# Check if this specific model's distance exceeds cap (with floating-point tolerance)
	if total_distance_for_model > effective_cap + MOVEMENT_CAP_EPSILON:
		log_phase_message("  FAILED: Distance %.1f\" exceeds cap %.1f\" (pivot cost: %.0f\")" % [total_distance_for_model, effective_cap, move_data.get("pivot_value", 0.0) if move_data.get("pivot_cost_applied", false) else 0.0])
		return {"valid": false, "errors": ["Model %s would exceed movement cap: %.1f\" > %.1f\"" % [model_id, total_distance_for_model, effective_cap]]}
	
	# Check engagement range restrictions for the destination
	var er_check = _check_engagement_range_at_position(unit_id, model_id, dest_vec, move_data.mode)
	if not er_check.valid:
		return {"valid": false, "errors": er_check.errors}

	# 10e Rule: Normal Move and Advance cannot cross enemy model bases
	# FLY units are exempt — they can move over enemy models
	# Fall Back and Surge are also exempt (Fall Back handled via Desperate Escape,
	# Surge moves allow moving through/into Engagement Range)
	if move_data.mode in ["NORMAL", "ADVANCE"] and not _unit_has_fly_keyword(unit_id) and not _o6_moves_through_models(unit_id, move_data):
		if _path_crosses_enemy_bases(current_pos, dest_vec, unit_id, model):
			log_phase_message("  FAILED: Path crosses enemy model base (Normal/Advance cannot move through enemies)")
			return {"valid": false, "errors": ["Cannot move through enemy models during Normal Move or Advance"]}

	# 10e Errata: Cannot move across MONSTER or VEHICLE models (friendly or enemy)
	# FLY units are exempt
	if not _unit_has_fly_keyword(unit_id) and not _o6_moves_through_models(unit_id, move_data):
		if _path_crosses_monster_vehicle_bases(current_pos, dest_vec, unit_id, model):
			log_phase_message("  FAILED: Path crosses friendly/enemy Monster/Vehicle model base")
			return {"valid": false, "errors": ["Cannot move through Monster or Vehicle models"]}

	# Check terrain collision
	if _position_intersects_terrain(dest_vec, model):
		return {"valid": false, "errors": ["Position intersects impassable terrain"]}

	# Check model overlap. Pass model_actual_unit_id, NOT unit_id: the overlap
	# scan skips the moving model by (unit_id, model_id), and an attached
	# character shares the bodyguard's model ids. Keyed on the bodyguard the
	# character was never skipped, so he "overlapped" HIMSELF at his old spot and
	# no move of his could ever stage — every group move left him behind, and the
	# squadmates whose destinations he was still standing in were blocked too.
	if _position_overlaps_other_models(model_actual_unit_id, model_id, dest_vec, model):
		return {"valid": false, "errors": ["Cannot end move on top of another model"]}

	# Check wall overlap — no model may end its move overlapping a wall
	# (path-traversal honors per-keyword blocks_movement separately). Mirrors
	# the client-side gate in MovementController._end_model_drag; required
	# here so STAGE_MODEL_MOVE actions dispatched without the drag UI
	# (multiplayer, tests, AI) still hit the same rule. Keywords make the
	# 11e solid-feature half of the check keyword-aware (infantry exempt).
	var _wall_test_model_stage = model.duplicate(true)
	_wall_test_model_stage["position"] = dest_vec
	if Measurement.model_overlaps_any_wall(_wall_test_model_stage, _terrain_rule_keywords(unit_id, move_data)):
		log_phase_message("  FAILED: Model would end move overlapping a wall")
		return {"valid": false, "errors": ["Cannot end move overlapping a wall"]}

	# Check board edge - no part of model base can extend beyond the battlefield
	if _position_outside_board_bounds(dest_vec, model):
		log_phase_message("  FAILED: Model would extend beyond board edge")
		return {"valid": false, "errors": ["Model cannot be placed beyond the board edge"]}

	return {"valid": true, "errors": []}

## T03 BEGIN_MODEL_DRAG — pick a model of a moving unit up: what a mouse press on
## it does, as an action (scenarios, the MCP bridge, tooling). Legal while the
## unit has an unfinished move it can still drag in, for a live model of the
## unit or of a CHARACTER attached to it. The real mouse drag never sends it, so
## a player's drag costs no action round trip.
## payload: {model_id, model_source_unit_id?}
func _validate_begin_model_drag(action: Dictionary) -> Dictionary:
	var unit_id: String = str(action.get("actor_unit_id", ""))
	var payload: Dictionary = action.get("payload", {})
	var model_id: String = str(payload.get("model_id", ""))
	if unit_id == "" or model_id == "":
		return {"valid": false, "errors": ["Missing required fields (actor_unit_id, payload.model_id)"]}
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["No active move for unit %s — begin its move first" % unit_id]}
	var move_data: Dictionary = active_moves[unit_id]
	if move_data.get("completed", false) or str(move_data.get("mode", "")) == "REMAIN_STATIONARY":
		return {"valid": false, "errors": ["Unit %s has no move left to drag" % unit_id]}
	var owner_unit_id := _begin_model_drag_owner(unit_id, model_id, str(payload.get("model_source_unit_id", "")))
	if owner_unit_id == "":
		return {"valid": false, "errors": ["Model %s is not a model of %s or a character attached to it" % [model_id, unit_id]]}
	if not _get_model_in_unit(owner_unit_id, model_id).get("alive", true):
		return {"valid": false, "errors": ["Model %s is destroyed" % model_id]}
	return {"valid": true, "errors": []}

## The unit that owns model_id for a BEGIN_MODEL_DRAG on unit_id: the named
## source unit when it is unit_id or a CHARACTER attached to it, else unit_id,
## else the first attached CHARACTER holding that model id. "" when none does.
func _begin_model_drag_owner(unit_id: String, model_id: String, source_unit_id: String) -> String:
	var attached: Array = get_unit(unit_id).get("attachment_data", {}).get("attached_characters", [])
	if source_unit_id != "" and (source_unit_id == unit_id or source_unit_id in attached):
		if not _get_model_in_unit(source_unit_id, model_id).is_empty():
			return source_unit_id
	if not _get_model_in_unit(unit_id, model_id).is_empty():
		return unit_id
	for char_id in attached:
		if not _get_model_in_unit(str(char_id), model_id).is_empty():
			return str(char_id)
	return ""

func _validate_undo_last_model_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["No active move for unit"]}
	
	var move_data = active_moves[unit_id]
	if move_data.model_moves.is_empty() and move_data.staged_moves.is_empty():
		return {"valid": false, "errors": ["No model moves to undo"]}

	return {"valid": true, "errors": []}

func _validate_reset_unit_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["No active move for unit"]}
	
	return {"valid": true, "errors": []}

func _validate_confirm_unit_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["No active move for unit"]}

	var move_data = active_moves[unit_id]

	# For Fall Back, ensure all models end outside engagement range
	if move_data.mode == "FALL_BACK":
		for model_move in move_data.model_moves:
			var dest = model_move.dest
			if _is_position_in_engagement_range(unit_id, model_move.model_id, dest):
				return {"valid": false, "errors": ["Model %s would still be in engagement range" % model_move.model_id]}

	# Check unit coherency after all staged moves are applied
	# Rule: Each model must be within 2" horizontally and 5" vertically of at least one other model (2 others for 7+ model units)
	var coherency_result = _validate_unit_coherency_after_move(unit_id, move_data)
	if not coherency_result.valid:
		return {"valid": false, "errors": coherency_result.errors}

	return {"valid": true, "errors": []}

func _check_models_coherency(final_models: Array) -> Dictionary:
	"""Check unit coherency for an array of model dicts with positions (11e core rules 03.03):
	every model must be within 2" horizontally / 5" vertically of at least one other model AND
	within 9" of every other model in the unit. Delegates to the edition-aware
	AttackSequence.check_unit_coherency() single source of truth. Returns {valid, errors}."""
	if final_models.size() <= 1:
		return {"valid": true, "errors": []}

	var result = AttackSequence.check_unit_coherency({"models": final_models})
	if result.get("coherent", true):
		return {"valid": true, "errors": []}

	var offenders = result.get("offenders", [])
	log_phase_message("Coherency check failed: %d model(s) out of coherency (%s)" % [offenders.size(), ", ".join(offenders)])
	return {"valid": false, "errors": ["Unit coherency broken: %d model(s) out of coherency — every model must be within 2\" of a mate AND within 9\" of every other model in the unit" % offenders.size()]}

func _validate_unit_coherency_after_move(unit_id: String, move_data: Dictionary) -> Dictionary:
	"""Validate that the unit maintains coherency after all staged moves are applied.
	Returns {valid: bool, errors: Array} — rejects the move if coherency is broken."""
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}

	var models = unit.get("models", [])
	var alive_models = []
	for model in models:
		if model.get("alive", true):
			alive_models.append(model)

	# Single model units are always coherent
	if alive_models.size() <= 1:
		return {"valid": true, "errors": []}

	# Build a map of model_id -> staged destination
	var staged_positions = {}
	for staged_move in move_data.get("staged_moves", []):
		staged_positions[staged_move.model_id] = staged_move.dest

	# Build final model dicts with their post-move positions
	var final_models = []
	for model in alive_models:
		var model_id = model.get("id", "")
		var final_model = model.duplicate()
		if staged_positions.has(model_id):
			final_model["position"] = staged_positions[model_id]
		final_models.append(final_model)

	return _check_models_coherency(final_models)

func _validate_remain_stationary(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}
	
	if unit.get("flags", {}).get("moved", false):
		return {"valid": false, "errors": ["Unit has already acted this phase"]}
	
	return {"valid": true, "errors": []}

func _validate_end_movement(action: Dictionary) -> Dictionary:
	# Codex: Adeptus Custodes ARCHEOTECH TELEPORT-SHUNTER (CustodesAbilities.gd): the unit must make its ingress move this phase.
	var cus11e_ingress: Array = _cus11e_abilities().pending_forced_ingress(get_current_player())
	if not cus11e_ingress.is_empty():
		return {"valid": false, "errors": ["%s must make an ingress move this phase (Archeotech Teleport-shunter) — set it up from reserves first" % ", ".join(PackedStringArray(cus11e_ingress.map(func(x): return GameState.get_unit_display_name(str(x)))))]}
	# Check if there are any active moves that need to be resolved
	# Only incomplete moves should block phase end
	# NOTE: Check both local active_moves AND synced GameState to ensure multiplayer compatibility

	log_phase_message("=== END_MOVEMENT VALIDATION START ===")
	log_phase_message("Active moves count: %d" % active_moves.size())
	log_phase_message("Active moves keys: %s" % str(active_moves.keys()))

	# Get all deployed units for current player
	var current_player = get_current_player()
	var all_units = get_units_for_player(current_player)
	log_phase_message("Total deployed units for player %d: %d" % [current_player, all_units.size()])

	# Check which units have moved
	var moved_count = 0
	var unacted_count = 0
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
			continue
		var has_moved = unit.get("flags", {}).get("moved", false)
		if has_moved:
			moved_count += 1
			log_phase_message("  ✓ Unit %s has moved" % unit_id)
		else:
			unacted_count += 1
			log_phase_message("  ✗ Unit %s has NOT moved (not marked in flags)" % unit_id)

	log_phase_message("Summary: %d moved, %d not moved" % [moved_count, unacted_count])

	# Check local active_moves for uncommitted staged/model moves
	for unit_id in active_moves:
		var move_data = active_moves[unit_id]
		# Check if unit has been marked as moved in GameState (synced across network)
		var unit = get_unit(unit_id)
		var has_moved = unit.get("flags", {}).get("moved", false)
		var unit_name = unit.get("meta", {}).get("name", unit_id)

		log_phase_message("Checking active_move for unit %s (%s)" % [unit_id, unit_name])
		log_phase_message("  - flags.moved: %s" % str(has_moved))
		log_phase_message("  - flags.movement_active: %s" % str(unit.get("flags", {}).get("movement_active", false)))
		log_phase_message("  - staged_moves: %d" % move_data.get("staged_moves", []).size())
		log_phase_message("  - model_moves: %d" % move_data.get("model_moves", []).size())
		log_phase_message("  - completed flag (local): %s" % str(move_data.get("completed", false)))

		# If not marked as moved in GameState, check if move was actually started
		if not has_moved:
			# Allow ending if no models have been moved (just initialized but not acted on)
			if move_data.get("staged_moves", []).is_empty() and move_data.get("model_moves", []).is_empty():
				# Unit was initialized for movement but never actually moved - this is OK
				log_phase_message("  → ALLOWING: Movement initialized but no models moved")
				continue

			# Unit has staged or committed moves that haven't been confirmed
			log_phase_message("  → BLOCKING: Unit has uncommitted moves!")
			log_phase_message("=== END_MOVEMENT VALIDATION FAILED ===")
			return {"valid": false, "errors": ["There are active moves that need to be confirmed or reset"]}

	# Also check synced GameState for any units with movement_active but not moved (T2-12)
	# This catches cases where the client's active_moves dict is out of sync with the host
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if unit.get("flags", {}).get("movement_active", false) and not unit.get("flags", {}).get("moved", false):
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			log_phase_message("  → BLOCKING (via GameState): Unit %s (%s) has movement_active=true but moved=false" % [unit_id, unit_name])
			log_phase_message("=== END_MOVEMENT VALIDATION FAILED ===")
			return {"valid": false, "errors": ["There are active moves that need to be confirmed or reset"]}

	# 09.02: units still unselected are resolved as Remain Stationary by
	# _process_end_movement (09.04: any unit is eligible), so they do not block.
	var unselected = get_units_requiring_selection(current_player)
	if not unselected.is_empty():
		log_phase_message("%d unit(s) not yet selected — END_MOVEMENT will resolve them as Remain Stationary (09.02/09.04): %s" % [unselected.size(), str(unselected)])
	log_phase_message("=== END_MOVEMENT VALIDATION PASSED ===")
	return {"valid": true, "errors": []}

# Processing Methods

func _process_begin_normal_move(action: Dictionary) -> Dictionary:
	# Codex: Orks (11e) unit_selected_to_move window — before the move cap is computed.
	var stm := _ork11e_open_selected_to_move_windows(action, "normal")
	if stm.paused:
		return create_result(true, stm.diffs)
	return _ork11e_merge_diffs(_process_begin_normal_move_after_windows(action), stm.diffs)

## Everything that follows "selected to make a normal move" once the
## Codex: Orks (11e) windows have closed.
func _process_begin_normal_move_after_windows(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)
	var move_inches = get_unit_movement(unit)
	# ISS-061 (11e 21.03/24.17): "take to the skies" — an opt-in FLY
	# declaration per move (payload.take_to_skies): -2\" cap (0 with
	# HOVER); the mover ignores vertical distance and may move through
	# models and terrain (pathing consumers read took_to_skies).
	var took_to_skies := false
	if GameConstants.edition >= 11 and action.get("payload", {}).get("take_to_skies", false) \
			and "FLY" in GameState.get_unit(unit_id).get("meta", {}).get("keywords", []) \
			and not OrkAbilities11eScript.cannot_take_to_skies(unit_id):  # WP-O6 Madcap Artillery "grounded"
		took_to_skies = true
		var fly_mod = MoveType.take_to_skies_modifier(GameState.get_unit(unit_id))
		move_inches = max(0.0, move_inches + fly_mod)
		log_phase_message("[11e] %s takes to the skies: cap %s\" (%+.1f\"), may move through models and terrain" % [unit_id, str(move_inches), fly_mod])

	# ISS-073 (24.35): a SUPER-HEAVY WALKER may opt to grant all its models
	# the MOBILE keyword for this move (payload.shw_mobile_gamble) — letting
	# it move through dense terrain; at move end it rolls D6, on a 1 it is
	# battle-shocked. Recorded here, the D6 is rolled at CONFIRM.
	var shw_mobile: bool = GameConstants.edition >= 11 \
			and bool(action.get("payload", {}).get("shw_mobile_gamble", false)) \
			and UnitAbilities.is_super_heavy_walker(GameState.get_unit(unit_id))  # keyword or the 24.35 core ability
	# If unit already had staged moves (e.g. switching modes), reset visuals first
	_reset_staged_visuals_if_needed(unit_id)

	var pivot_value = get_pivot_value_for_unit(unit_id)
	active_moves[unit_id] = {
		"mode": "NORMAL",
		"took_to_skies": took_to_skies,
		"shw_mobile": shw_mobile,
		"mode_locked": false,  # Track if mode is confirmed
		"completed": false,  # Track if unit has completed movement
		"move_cap_inches": move_inches,
		"advance_roll": 0,  # Store advance dice result
		"model_moves": [],
		"staged_moves": [],  # NEW: Temporary moves before confirmation
		"original_positions": {},  # NEW: Track starting positions for reset
		"original_rotations": {},  # Track starting rotations for reset
		"model_distances": {},  # NEW: Track per-model distances
		"dice_rolls": [],
		# Pivot tracking (10e Core Rules Update)
		"pivot_value": pivot_value,  # Cost in inches for first pivot (0, 1, or 2)
		"pivot_cost_applied": false,  # Whether pivot cost has been deducted this move
		# Multi-selection group movement support
		"group_moves": [],  # Track group movement operations
		"group_selection": [],  # Current multi-selected models
		"group_formation": {}  # Relative positions within group
	}
	if pivot_value > 0:
		log_phase_message("  Pivot value for %s: %.0f\"" % [unit.get("meta", {}).get("name", unit_id), pivot_value])

	emit_signal("unit_move_begun", unit_id, "NORMAL")
	log_phase_message("Beginning normal move for %s (M: %d\")" % [unit.get("meta", {}).get("name", unit_id), move_inches])

	var begin_changes = [
		{
			"op": "set",
			"path": "units.%s.flags.move_cap_inches" % unit_id,
			"value": move_inches
		},
		{
			"op": "set",
			"path": "units.%s.flags.movement_active" % unit_id,
			"value": true
		}
	]

	# P2-88: Check for Fire Overwatch at move start
	# Balance Dataslate timing: "when an enemy unit starts a Normal move"
	var ow_result = _check_fire_overwatch_opportunity(unit_id, "normal move start")
	if ow_result.triggered:
		var result = create_result(true, begin_changes)
		result.merge(ow_result.result_extra)
		return result

	return create_result(true, begin_changes)

func _process_begin_advance(action: Dictionary) -> Dictionary:
	# Codex: Orks (11e) unit_selected_to_move window — before the advance roll.
	var stm := _ork11e_open_selected_to_move_windows(action, "advance")
	if stm.paused:
		return create_result(true, stm.diffs)
	return _ork11e_merge_diffs(_process_begin_advance_after_windows(action), stm.diffs)

## Everything that follows "selected to make an advance move" once the
## Codex: Orks (11e) windows have closed.
func _process_begin_advance_after_windows(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)
	var move_inches = get_unit_movement(unit)
	# ISS-061 (11e): record the take-to-the-skies declaration; the cap is
	# applied in _resolve_advance_roll (after the D6 and any rerolls).
	_pending_take_to_skies[unit_id] = GameConstants.edition >= 11 \
			and action.get("payload", {}).get("take_to_skies", false) \
			and "FLY" in GameState.get_unit(unit_id).get("meta", {}).get("keywords", []) \
			and not OrkAbilities11eScript.cannot_take_to_skies(unit_id)  # WP-O6 Madcap Artillery "grounded"
	_pending_shw_mobile[unit_id] = GameConstants.edition >= 11 \
			and action.get("payload", {}).get("shw_mobile_gamble", false) \
			and UnitAbilities.is_super_heavy_walker(GameState.get_unit(unit_id))  # keyword or the 24.35 core ability

	# Turbo Boostas (Speedwaaagh! detachment rule): a SPEED FREEKS or TRUKK
	# unit (excluding AIRCRAFT) can use its turbo instead of rolling — Move
	# becomes a flat 24" this phase, ranged weapons gain ASSAULT until end of
	# turn and the unit cannot declare a charge. The one-straight-line /
	# no-pivot rider is not enforced (documented simplification).
	_pending_turbo_boost[unit_id] = GameConstants.edition >= 11 \
			and action.get("payload", {}).get("turbo_boost", false) \
			and FactionAbilityManager.unit_can_turbo_boost(unit)

	# If unit already had staged moves (e.g. switching from Normal to Advance), reset visuals early
	# This ensures visuals are correct even if a reroll dialog delays _resolve_advance_roll
	_reset_staged_visuals_if_needed(unit_id)

	# NOTE: P2-88 move-start overwatch trigger is not applied here because the advance
	# move flow immediately rolls dice and may offer a command reroll, making the
	# interrupt-and-resume flow overly complex. The move-end trigger in
	# _process_confirm_unit_move covers the Advance move case.

	# Turbo Boostas (Speedwaaagh!): no Advance roll — Move becomes a flat 24"
	# for this phase. Takes precedence over auto-advance abilities because the
	# player explicitly declared the turbo.
	if _pending_turbo_boost.get(unit_id, false):
		var tb_name = unit.get("meta", {}).get("name", unit_id)
		log_phase_message("Advance: %s uses its turbo (Turbo Boostas) — no roll, flat 24\" move" % tb_name)
		DebugLogger.info(str("MovementPhase: Turbo Boostas — %s turbo-boosts (flat 24\" move, no roll)" % tb_name))
		var gel_tb = get_node_or_null("/root/GameEventLog")
		if gel_tb:
			gel_tb.add_player_entry(int(unit.get("owner", 0)),
				"%s turbo-boosts (Speedwaaagh!): 24\" move, ranged weapons gain ASSAULT, cannot charge" % tb_name)
		return _resolve_advance_roll(unit_id, 0, false)

	# OA-5: Boardin' Rush — skip advance roll, add flat 6" to Move instead
	var flags = unit.get("flags", {})
	if flags.get("effect_boardin_rush", false):
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		log_phase_message("Advance: %s → Boardin' Rush active — skip roll, +6\" to Move" % unit_name)
		DebugLogger.info(str("MovementPhase: Boardin' Rush — %s advances with flat +6\" (no roll)" % unit_name))
		# Log to GameEventLog
		var game_event_log = get_node_or_null("/root/GameEventLog")
		if game_event_log:
			var owner = int(unit.get("owner", 0))
			game_event_log.add_player_entry(owner,
				"%s advances (Boardin' Rush): +6\", total move = %d\" (M %d\" + 6\")" % [
					unit_name, int(move_inches + 6), int(move_inches)])
		return _resolve_advance_roll(unit_id, 6, false)

	# Turbo-boost / Fuel-mixa Grot / High-octane Fuel — skip advance roll, auto +6" to Move
	if EffectPrimitivesData.has_effect_flat_advance(unit) or EffectPrimitivesData.has_effect_auto_advance_6(unit):
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		log_phase_message("Advance: %s → auto advance ability active — skip roll, +6\" to Move" % unit_name)
		DebugLogger.info(str("MovementPhase: Auto Advance 6 — %s advances with flat +6\" (no roll)" % unit_name))
		var game_event_log = get_node_or_null("/root/GameEventLog")
		if game_event_log:
			var owner = int(unit.get("owner", 0))
			game_event_log.add_player_entry(owner,
				"%s advances (auto +6\"): total move = %d\" (M %d\" + 6\")" % [
					unit_name, int(move_inches + 6), int(move_inches)])
		return _resolve_advance_roll(unit_id, 6, false)

	# WP-O6 SHOKK-BOOSTA (Codex: Orks 11e, Big Mek): "This unit can change that
	# advance roll to a 6" — used in the unit_selected_to_move window just
	# answered; the 6 is an advance roll, so roll modifiers still apply.
	if GameConstants.edition >= 11 and OrkAbilities11eScript.shokk_boosta_active(unit_id):
		log_phase_message("Advance: %s → Shokk-boosta — advance roll is a 6" % unit.get("meta", {}).get("name", unit_id))
		return _resolve_advance_roll(unit_id, 6, true)

	# WP-S4 WIND WALKER (Space Wolves, Njal Stormcaller): "this unit can change
	# advance rolls to a 6" — always taken; it is a roll, so modifiers apply.
	if _sw11e_abilities().advance_roll_six(unit_id):
		log_phase_message("Advance: %s → Wind Walker — advance roll changed to a 6" % unit.get("meta", {}).get("name", unit_id))
		return _resolve_advance_roll(unit_id, 6, true)

	# Codex: Space Marines (11e) SUDDEN ONSLAUGHT (SMCodex11e.gd): "can change its
	# advance rolls to a 6" — used in the unit_selected_to_move window just answered.
	if _sm11e_codex().advance_roll_six(unit_id):
		log_phase_message("Advance: %s → Sudden Onslaught — advance roll changed to a 6" % unit.get("meta", {}).get("name", unit_id))
		GameEventLog.add_player_entry(int(unit.get("owner", 0)), "SUDDEN ONSLAUGHT: %s's advance roll is a 6" % unit.get("meta", {}).get("name", unit_id))
		return _resolve_advance_roll(unit_id, 6, true)
	# WP-M4b VEIL OF TIME (Codex: Space Marines 11e, Librarian; psychic, used in
	# the unit_selected_to_move window just answered): "this unit can change that
	# advance roll to a 6" — a roll, so modifiers still apply.
	if load("res://scripts/codex/space_marines/SMAbilitiesB.gd").veil_of_time_active(unit_id):
		log_phase_message("Advance: %s → Veil of Time — advance roll changed to a 6" % unit.get("meta", {}).get("name", unit_id))
		return _resolve_advance_roll(unit_id, 6, true)

	# Roll D6 for advance (with deterministic seed for multiplayer)
	# T5-MP9: Read seed from action payload (embedded by NetworkManager.submit_action)
	# so both optimistic client and authoritative host produce the same roll.
	var rng_seed = action.get("payload", {}).get("rng_seed", -1)
	if rng_seed == -1:
		# Fallback: if no seed in payload (e.g. single-player), check host generation
		if has_node("/root/NetworkManager"):
			var net_mgr = get_node("/root/NetworkManager")
			if net_mgr.is_networked() and net_mgr.is_host():
				rng_seed = net_mgr.get_next_rng_seed()

	var rng_service = RulesEngine.RNGService.new(rng_seed)
	var rolls = rng_service.roll_d6(1)
	var advance_roll = rolls[0]
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	log_phase_message("Advance: %s → D6 = %d" % [unit_name, advance_roll])

	# THUNDERING WAGONS (Rollin' Deff): the rigs do not roll for Advance —
	# their Advance is a flat 6".
	var tw_override = FactionAbilityManager.get_thundering_wagons_advance_override(unit)
	if tw_override > 0:
		advance_roll = tw_override
		log_phase_message("Advance: %s — Thundering Wagons, flat %d\" (no roll)" % [unit_name, tw_override])
	# Codex: Orks (11e) Blitz Brigade — Unstoppable Momentum: a WAGON's advance roll is changed to a 6 (WP-O34).
	var ork11e_roll_changed := false
	if tw_override == 0 and Ork11eDetachments.advance_roll_override(unit) > 0 and advance_roll < 6:
		log_phase_message("Advance: %s — Unstoppable Momentum: advance roll %d changed to a 6" % [unit_name, advance_roll])
		Ork11eDetachments.report_advance_roll_changed(unit_id, advance_roll)
		advance_roll = Ork11eDetachments.advance_roll_override(unit)
		tw_override = advance_roll  # a changed roll: no re-roll is offered below
		ork11e_roll_changed = true

	# Ability-granted Advance re-roll (Bloodthirsty Belligerence, SUPERFUELLED
	# BOILER, Blitz Brigade's Eager for the Fight after disembarking): the
	# re-roll must keep the second result, so auto re-roll only when the first
	# roll is low enough that a player always would (1-3).
	if tw_override == 0 and advance_roll <= 3 \
			and (EffectPrimitivesData.has_effect_reroll_advance(unit) or FactionAbilityManager.unit_has_detachment_advance_reroll(unit)):
		var reroll_result = rng_service.roll_d6(1)[0]
		log_phase_message("Advance re-roll (ability): %s re-rolls %d → %d" % [unit_name, advance_roll, reroll_result])
		advance_roll = reroll_result

	# Check if Command Re-roll is available
	var current_player = get_current_player()
	var strat_manager = get_node_or_null("/root/StratagemManager")
	var reroll_available = false
	# Codex: Orks (11e) Waaagh! — "can re-roll advance rolls": a free, optional
	# re-roll offered in the same dialog instead of the Command Re-roll (WP-O34).
	var free_rr_source: String = Ork11eArmyRules.free_advance_reroll_source(unit) if tw_override == 0 and advance_roll < 6 \
		and not (EffectPrimitivesData.has_effect_reroll_advance(unit) or FactionAbilityManager.unit_has_detachment_advance_reroll(unit)) else ""
	# WP-M2a Codex: Space Marines (11e) Wrath of the Chapter / Supercharged Engines: "can re-roll advance rolls" (free).
	if free_rr_source == "" and tw_override == 0 and advance_roll < 6 and GameConstants.edition >= 11 and not (EffectPrimitivesData.has_effect_reroll_advance(unit) or FactionAbilityManager.unit_has_detachment_advance_reroll(unit)):
		free_rr_source = str(load("res://scripts/codex/space_marines/SMDetachmentsA.gd").free_advance_reroll_source(unit))
	# WP-M2b: Codex: Space Marines (11e) Honour of Vigilance (devastator doctrine): "can re-roll advance rolls" — same free re-roll.
	if free_rr_source == "" and tw_override == 0 and advance_roll < 6 and not (EffectPrimitivesData.has_effect_reroll_advance(unit) or FactionAbilityManager.unit_has_detachment_advance_reroll(unit)):
		free_rr_source = str(load("res://scripts/codex/space_marines/SMDetachmentsB.gd").free_advance_reroll_source(unit))
	if strat_manager and free_rr_source == "" and not ork11e_roll_changed:  # (WP-O34: a changed 6 is not re-rolled)
		var reroll_check = strat_manager.is_command_reroll_available(current_player, unit_id)
		reroll_available = reroll_check.available
		if not reroll_available:
			DebugLogger.info(str("MovementPhase: Command Re-roll not offered for %s advance — %s" % [unit_name, str(reroll_check.get("reason", ""))]))
	if free_rr_source != "":
		reroll_available = true
		DebugLogger.info(str("MovementPhase: %s free advance re-roll offered for %s (rolled %d)" % [free_rr_source, unit_name, advance_roll]))

	if reroll_available:
		# Pause — store roll and offer Command Re-roll
		_awaiting_reroll_decision = true
		_reroll_pending_unit_id = unit_id
		_reroll_pending_data = {
			"advance_roll": advance_roll,
			"move_inches": move_inches,
			"unit_id": unit_id,
			"unit_name": unit_name,
			"free_ability": free_rr_source,  # Codex: Orks (11e) Waaagh! free re-roll (no CP) — WP-O34
		}

		# Codex: Orks (11e) 'ERE WE GO's +2 applies after any re-roll — show it.
		var ctx_bonus := int(unit.get("flags", {}).get(Ork11eMovement.FLAG_ERE_WE_GO, 0)) if tw_override == 0 else 0
		var context_text = "Advance roll: %d (M %d\" + %d\" = %d\" total)" % [advance_roll, int(move_inches), advance_roll, int(move_inches + advance_roll)]
		if ctx_bonus != 0:
			context_text = "Advance roll: %d %+d (M %d\" + %d\" = %d\" total)" % [advance_roll, ctx_bonus, int(move_inches), advance_roll + ctx_bonus, int(move_inches + advance_roll + ctx_bonus)]
		var roll_context = {
			"roll_type": "advance_roll",
			"original_rolls": [advance_roll],
			"total": advance_roll,
			"unit_id": unit_id,
			"unit_name": unit_name,
			"context_text": context_text,
			"free_ability_name": free_rr_source,  # Codex: Orks (11e) Waaagh! free re-roll — WP-O34
		}

		DebugLogger.info(str("MovementPhase: Command Re-roll available for %s advance — pausing for decision" % unit_name))
		emit_signal("command_reroll_opportunity", unit_id, current_player, roll_context)

		return create_result(true, [], "", {
			"dice": [{"context": "advance", "n": 1, "rolls": [advance_roll]}],
			"awaiting_reroll": true,
		})

	# No reroll available — resolve immediately
	return _resolve_advance_roll(unit_id, advance_roll)

func _resolve_advance_roll(unit_id: String, advance_roll: int, is_roll: bool = true) -> Dictionary:
	"""Resolve an advance roll with the given die value. is_roll = false for the
	flat Advance values that replace the roll (Turbo Boostas, Boardin' Rush,
	auto-advance 6) — roll modifiers do not apply to those."""
	var unit = get_unit(unit_id)
	var move_inches = get_unit_movement(unit)
	# ISS-061 (11e 21.03/24.17): apply the recorded take-to-the-skies cap.
	var took_to_skies: bool = _pending_take_to_skies.get(unit_id, false)
	_pending_take_to_skies.erase(unit_id)
	var shw_mobile: bool = _pending_shw_mobile.get(unit_id, false)
	_pending_shw_mobile.erase(unit_id)
	if took_to_skies:
		var fly_mod = MoveType.take_to_skies_modifier(GameState.get_unit(unit_id))
		move_inches = max(0.0, move_inches + fly_mod)
		log_phase_message("[11e] %s takes to the skies: advance cap (%s + %d)\" (%+.1f\")" % [unit_id, str(move_inches), advance_roll, fly_mod])
	# Turbo Boostas (Speedwaaagh!): Move characteristic becomes a flat 24"
	# for this phase (replaces M entirely; no Advance roll was made).
	var turbo_boost: bool = _pending_turbo_boost.get(unit_id, false)
	_pending_turbo_boost.erase(unit_id)
	if turbo_boost:
		move_inches = 24.0
		log_phase_message("[Speedwaaagh!] %s turbo-boosts: Move = flat 24\" this phase" % unit_id)
	# Codex: Orks (11e) 'ERE WE GO: "+2 to advance rolls" — a modifier, applied
	# after any re-roll (01.05.03) and only when an advance roll was made.
	var ewg_bonus := int(unit.get("flags", {}).get(Ork11eMovement.FLAG_ERE_WE_GO, 0))
	if ewg_bonus != 0 and is_roll:
		var ewg_raw := advance_roll
		advance_roll += ewg_bonus
		log_phase_message("'ERE WE GO: %s advance roll %d %+d = %d" % [unit_id, ewg_raw, ewg_bonus, advance_roll])
		dice_log.append({"unit_id": unit_id, "unit_name": unit.get("meta", {}).get("name", unit_id),
			"type": "'ERE WE GO", "roll": ewg_raw, "result": "Advance roll %d %+d = %d" % [ewg_raw, ewg_bonus, advance_roll]})
	# Codex: Adeptus Custodes (11e) Auric Eagle (Solar Watch): +1 to advance
	# rolls — a modifier, after any re-roll, only on a real roll (WP-C46).
	var cus11e_ab: int = int(_cus11e_det().advance_roll_bonus(unit))
	if cus11e_ab != 0 and is_roll:
		var ae_raw := advance_roll
		advance_roll += cus11e_ab
		log_phase_message("Auric Eagle: %s advance roll %d %+d = %d" % [unit_id, ae_raw, cus11e_ab, advance_roll])
		dice_log.append({"unit_id": unit_id, "unit_name": unit.get("meta", {}).get("name", unit_id),
			"type": "Auric Eagle", "roll": ae_raw, "result": "Advance roll %d %+d = %d" % [ae_raw, cus11e_ab, advance_roll]})
	# Codex: Space Marines (11e) Encircling Jaws (Master of Wolves, assault doctrine): +1 to advance rolls (WP-S2).
	var sw11e_ab: int = int(load("res://scripts/codex/space_wolves/SWDetachments11e.gd").advance_roll_bonus(unit)) if (is_roll and GameConstants.edition >= 11) else 0
	if sw11e_ab != 0:
		var ej_raw := advance_roll
		advance_roll += sw11e_ab
		log_phase_message("Encircling Jaws: %s advance roll %d %+d = %d" % [unit_id, ej_raw, sw11e_ab, advance_roll])
		dice_log.append({"unit_id": unit_id, "unit_name": unit.get("meta", {}).get("name", unit_id),
			"type": "Encircling Jaws", "roll": ej_raw, "result": "Advance roll %d %+d = %d" % [ej_raw, sw11e_ab, advance_roll]})
	# WP-O6 FUEL-MIXA GROT (Codex: Orks 11e, Deffkilla Wartrike): "+1 to advance rolls".
	var o6_adv := OrkAbilities11eScript.advance_roll_bonus(unit_id) if (is_roll and GameConstants.edition >= 11) else 0
	if o6_adv != 0:
		var o6_raw := advance_roll
		advance_roll += o6_adv
		log_phase_message("Fuel-mixa Grot: %s advance roll %d %+d = %d" % [unit_id, o6_raw, o6_adv, advance_roll])
		dice_log.append({"unit_id": unit_id, "unit_name": unit.get("meta", {}).get("name", unit_id),
			"type": "Fuel-mixa Grot", "roll": o6_raw, "result": "Advance roll %d %+d = %d" % [o6_raw, o6_adv, advance_roll]})
	# WP-S4 FERVOUR OF THE ANCIENTS (Space Wolves, Venerable Dreadnought): +1 to advance rolls within 6".
	var sw_fv: Dictionary = _sw11e_abilities().fervour_bonus(unit_id) if is_roll else {"bonus": 0}
	if int(sw_fv.get("bonus", 0)) != 0:
		var sw_raw := advance_roll
		advance_roll += int(sw_fv.bonus)
		log_phase_message("%s: %s advance roll %d %+d = %d" % [str(sw_fv.source), unit_id, sw_raw, int(sw_fv.bonus), advance_roll])
		dice_log.append({"unit_id": unit_id, "unit_name": unit.get("meta", {}).get("name", unit_id),
			"type": "Fervour of the Ancients", "roll": sw_raw, "result": "Advance roll %d %+d = %d" % [sw_raw, int(sw_fv.bonus), advance_roll]})
	# WP-M4c SPEAR OF CHOGORIS (Suboden Khan): assault doctrine active -> +1 to advance rolls (SMAbilitiesC).
	var smc_rb: Dictionary = load("res://scripts/codex/space_marines/SMAbilitiesC.gd").roll_bonus(unit_id) if is_roll else {"bonus": 0}
	if int(smc_rb.get("bonus", 0)) != 0:
		var smc_raw := advance_roll
		advance_roll += int(smc_rb.bonus)
		log_phase_message("%s: %s advance roll %d %+d = %d" % [str(smc_rb.source), unit_id, smc_raw, int(smc_rb.bonus), advance_roll])
		dice_log.append({"unit_id": unit_id, "unit_name": unit.get("meta", {}).get("name", unit_id),
			"type": "Spear of Chogoris", "roll": smc_raw, "result": "Advance roll %d %+d = %d" % [smc_raw, int(smc_rb.bonus), advance_roll]})
	# WP-M4a ANGEL'S WRATH (Captain with Jump Pack): +1 to advance rolls (this unit).
	var sm_aw: Dictionary = _sm11e_abilities_a().roll_bonus(unit_id) if is_roll else {"bonus": 0}
	if int(sm_aw.get("bonus", 0)) != 0:
		var sm_raw := advance_roll
		advance_roll += int(sm_aw.bonus)
		log_phase_message("%s: %s advance roll %d %+d = %d" % [str(sm_aw.source), unit_id, sm_raw, int(sm_aw.bonus), advance_roll])
		dice_log.append({"unit_id": unit_id, "unit_name": unit.get("meta", {}).get("name", unit_id),
			"type": str(sm_aw.source), "roll": sm_raw, "result": "Advance roll %d %+d = %d" % [sm_raw, int(sm_aw.bonus), advance_roll]})
	var total_move = move_inches + advance_roll
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	# If unit already had staged moves (e.g. switching from Normal to Advance), reset visuals first
	_reset_staged_visuals_if_needed(unit_id)

	var pivot_value = get_pivot_value_for_unit(unit_id)
	active_moves[unit_id] = {
		"mode": "ADVANCE",
		"took_to_skies": took_to_skies,
		"shw_mobile": shw_mobile,
		"turbo_boost": turbo_boost,
		"mode_locked": false,
		"completed": false,
		"move_cap_inches": total_move,
		"advance_roll": advance_roll,
		"model_moves": [],
		"staged_moves": [],
		"original_positions": {},
		"original_rotations": {},
		"model_distances": {},
		"dice_rolls": [{"context": "advance", "rolls": [advance_roll]}],
		# Pivot tracking (10e Core Rules Update)
		"pivot_value": pivot_value,
		"pivot_cost_applied": false,
		"group_moves": [],
		"group_selection": [],
		"group_formation": {}
	}

	dice_log.append({
		"unit_id": unit_id,
		"unit_name": unit_name,
		"type": "Advance",
		"roll": advance_roll,
		"result": "Move cap = %d\" (M %d\" + %d\")" % [total_move, int(move_inches), advance_roll]
	})

	emit_signal("unit_move_begun", unit_id, "ADVANCE")
	log_phase_message("Advance: %s → D6 = %d → Move cap = %d\"" % [unit_name, advance_roll, total_move])

	# Log advance roll to GameEventLog
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		var owner = int(unit.get("owner", 0))
		if ewg_bonus != 0 and is_roll:
			# A modified roll: log the die as rolled ([N] renders as a die face)
			# plus the modifier — a [7] has no die face (EWG-2).
			game_event_log.add_player_entry(owner,
				"%s advances: rolled [%d] %+d ('ERE WE GO) = %d — total move = %d\" (M %d\" + %d\")" % [
					unit_name, advance_roll - ewg_bonus, ewg_bonus, advance_roll, total_move, int(move_inches), advance_roll])
		else:
			game_event_log.add_player_entry(owner,
				"%s advances: rolled [%d] — total move = %d\" (M %d\" + %d\")" % [
					unit_name, advance_roll, total_move, int(move_inches), advance_roll])

	return create_result(true, [
		{
			"op": "set",
			"path": "units.%s.flags.advanced" % unit_id,
			"value": true
		},
		{
			"op": "set",
			"path": "units.%s.flags.move_cap_inches" % unit_id,
			"value": total_move
		},
		{
			"op": "set",
			"path": "units.%s.flags.movement_active" % unit_id,
			"value": true
		}
	], "", {"dice": [{"context": "advance", "n": 1, "rolls": [advance_roll]}]})

func _process_use_command_reroll(action: Dictionary) -> Dictionary:
	"""Process USE_COMMAND_REROLL for advance roll."""
	var unit_id = _reroll_pending_unit_id
	var old_data = _reroll_pending_data.duplicate()
	_awaiting_reroll_decision = false
	_reroll_pending_unit_id = ""
	_reroll_pending_data = {}

	var unit_name = old_data.get("unit_name", unit_id)
	var old_roll = old_data.get("advance_roll", 0)
	var move_inches = old_data.get("move_inches", 0)
	var current_player = get_current_player()

	# Execute the stratagem (deduct CP, record usage) — unless this is the
	# Codex: Orks (11e) Waaagh! free advance re-roll (WP-O34: no CP, not a stratagem).
	var free_ability := str(old_data.get("free_ability", ""))
	var strat_manager = get_node_or_null("/root/StratagemManager") if free_ability == "" else null
	if free_ability != "":
		log_phase_message("%s: %s re-rolls its advance roll %d (free)" % [free_ability, unit_name, old_roll])
		var gel_free = get_node_or_null("/root/GameEventLog")
		if gel_free:
			gel_free.add_player_entry(current_player, "%s: %s re-rolls its advance roll (free) — was %d" % [free_ability, unit_name, old_roll])
	if strat_manager:
		var roll_context = {
			"roll_type": "advance_roll",
			"original_rolls": [old_roll],
			"unit_name": unit_name,
		}
		var strat_result = strat_manager.execute_command_reroll(current_player, unit_id, roll_context)
		if not strat_result.success:
			DebugLogger.info(str("MovementPhase: Command Re-roll failed: %s" % strat_result.get("error", "")))
			# Notify user of failure
			var toast_mgr = get_node_or_null("/root/ToastManager")
			if toast_mgr:
				toast_mgr.show_error("Command Re-roll failed: %s" % strat_result.get("error", "Unknown"))
			return _resolve_advance_roll(unit_id, old_roll)
	elif free_ability == "":
		DebugLogger.info("MovementPhase: WARNING — StratagemManager not found, cannot deduct CP")

	# Re-roll D6
	# Issue #329: honor payload.rng_seed
	var reroll_seed: int = action.get("payload", {}).get("rng_seed", -1)
	var rng_service = RulesEngine.RNGService.new(reroll_seed)
	var new_rolls = rng_service.roll_d6(1)
	var new_advance = new_rolls[0]

	var rr_label := ("%s FREE RE-ROLL" % free_ability.to_upper()) if free_ability != "" else "COMMAND RE-ROLL"
	var rr_cost := "free" if free_ability != "" else "1 CP"
	log_phase_message("%s: Advance re-rolled from %d → %d" % [rr_label, old_roll, new_advance])
	DebugLogger.info(str("MovementPhase: %s — %s advance re-rolled: %d → %d" % [rr_label, unit_name, old_roll, new_advance]))

	# P3-118: Emit reroll comparison data for visualization
	emit_signal("command_reroll_completed", [old_roll], [new_advance], "advance_roll")

	# Add reroll entry to dice log so it appears in the dice log panel
	dice_log.append({
		"unit_id": unit_id,
		"unit_name": unit_name,
		"type": "Command Re-roll" if free_ability == "" else "%s re-roll" % free_ability,
		"roll": new_advance,
		"result": "Advance rerolled: %d → %d (%s)" % [old_roll, new_advance, rr_cost]
	})

	# Show toast notification with reroll result
	# ('ERE WE GO's +2 is a modifier on the re-rolled value - include it.)
	var rr_ewg := int(get_unit(unit_id).get("flags", {}).get(Ork11eMovement.FLAG_ERE_WE_GO, 0))
	var new_total_move = int(move_inches) + new_advance + rr_ewg
	var toast_mgr = get_node_or_null("/root/ToastManager")
	if toast_mgr:
		toast_mgr.show_toast(
			"%s (%s): %s advance %d → %d%s (Move: %d\")" % [rr_label, rr_cost, unit_name, old_roll, new_advance,
				(" %+d 'ERE WE GO" % rr_ewg) if rr_ewg != 0 else "", new_total_move],
			Color.GOLD
		)

	return _resolve_advance_roll(unit_id, new_advance)

func _process_decline_command_reroll(action: Dictionary) -> Dictionary:
	"""Process DECLINE_COMMAND_REROLL for advance roll."""
	var unit_id = _reroll_pending_unit_id
	var old_data = _reroll_pending_data.duplicate()
	_awaiting_reroll_decision = false
	_reroll_pending_unit_id = ""
	_reroll_pending_data = {}

	var advance_roll = old_data.get("advance_roll", 0)
	var unit_name = old_data.get("unit_name", unit_id)
	var move_inches = old_data.get("move_inches", 0)
	# 'ERE WE GO's +2 modifies the kept roll - include it in the toast.
	var kept_ewg := int(get_unit(unit_id).get("flags", {}).get(Ork11eMovement.FLAG_ERE_WE_GO, 0))
	var total_move = int(move_inches) + advance_roll + kept_ewg

	DebugLogger.info(str("MovementPhase: Command Re-roll DECLINED for %s — resolving with original roll" % unit_id))

	# Show toast with original roll result
	var toast_mgr = get_node_or_null("/root/ToastManager")
	if toast_mgr:
		toast_mgr.show_toast(
			"%s advance roll: %d%s (Move: %d\")" % [unit_name, advance_roll,
				(" %+d 'ERE WE GO" % kept_ewg) if kept_ewg != 0 else "", total_move],
			Color.WHITE
		)

	return _resolve_advance_roll(unit_id, advance_roll)

# ============================================================================
# FIRE OVERWATCH (T3-11)
# ============================================================================

func _check_fire_overwatch_opportunity(unit_id: String, trigger_context: String, snapshot_override: Dictionary = {}) -> Dictionary:
	"""
	P2-88: Shared helper to check and offer Fire Overwatch.
	Balance Dataslate timing: 'just after an enemy unit is set up or when an enemy
	unit starts or ends a Normal, Advance or Fall Back move, or declares a charge.'

	Returns: { "triggered": bool, "result_extra": Dictionary }
	If triggered, the caller should merge result_extra into its result and return early.
	"""
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	# 11e 15.08 FIRE OVERWATCH — WHEN: "End of your opponent's Movement phase."
	# That is its only timing at edition >= 11: no per-move / set-up offer
	# (this Balance Dataslate timing is 10e-only). It is offered once, in the
	# movement_phase_end window opened by _complete_movement_phase.
	if GameConstants.edition >= 11:
		log_phase_message("[11e 15.08] no per-move Fire Overwatch offer (%s, %s) — it is offered at the end of the opponent's Movement phase" % [unit_name, trigger_context])
		return {"triggered": false}

	# P2-25: Sneaky Surprise — unit cannot be targeted by Fire Overwatch
	var _ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	var _has_sneaky_surprise = false
	if _ability_mgr:
		_has_sneaky_surprise = _ability_mgr.has_sneaky_surprise(unit_id)

	if _has_sneaky_surprise:
		log_phase_message("Sneaky Surprise: %s is immune to Fire Overwatch" % unit_name)
		DebugLogger.info(str("MovementPhase: Sneaky Surprise — %s cannot be targeted by Fire Overwatch" % unit_name))
		return {"triggered": false}

	var moving_owner = int(unit.get("owner", 0))
	var defending_player = 2 if moving_owner == 1 else 1

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if not strat_manager:
		return {"triggered": false}

	var ow_check = strat_manager.is_fire_overwatch_available(defending_player)
	if not ow_check.available:
		return {"triggered": false}

	# Use provided snapshot override or fall back to game_state_snapshot
	var check_snapshot = snapshot_override if not snapshot_override.is_empty() else game_state_snapshot

	var ow_eligible = strat_manager.get_fire_overwatch_eligible_units(
		defending_player, unit_id, check_snapshot
	)

	if ow_eligible.is_empty():
		return {"triggered": false}

	# Fire Overwatch is available! Pause and offer it to the defender
	_awaiting_fire_overwatch = true
	_awaiting_overwatch_decision = true
	_overwatch_moved_unit_id = unit_id
	_fire_overwatch_player = defending_player
	_fire_overwatch_enemy_unit_id = unit_id
	_fire_overwatch_eligible_units = ow_eligible
	log_phase_message("FIRE OVERWATCH available for Player %d (%d eligible units) against %s (%s)" % [defending_player, ow_eligible.size(), unit_name, trigger_context])
	DebugLogger.info(str("MovementPhase: Fire Overwatch opportunity — Player %d has %d eligible units (%s)" % [defending_player, ow_eligible.size(), trigger_context]))

	emit_signal("fire_overwatch_opportunity", defending_player, ow_eligible, unit_id)
	emit_signal("overwatch_opportunity", unit_id, defending_player, ow_eligible)

	return {
		"triggered": true,
		"result_extra": {
			"trigger_fire_overwatch": true,
			"awaiting_overwatch": true,
			"fire_overwatch_player": defending_player,
			"fire_overwatch_eligible_units": ow_eligible,
			"fire_overwatch_enemy_unit_id": unit_id,
		}
	}

func _validate_use_fire_overwatch(action: Dictionary) -> Dictionary:
	var errors = []
	var unit_id = action.get("unit_id", "")
	var player = action.get("player", _fire_overwatch_player)

	if not _awaiting_fire_overwatch and not _awaiting_overwatch_decision:
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
	if not _awaiting_fire_overwatch and not _awaiting_overwatch_decision:
		return {"valid": false, "errors": ["Not awaiting Fire Overwatch decision"]}
	return {"valid": true, "errors": []}

func _process_use_fire_overwatch(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var player = action.get("player", _fire_overwatch_player)
	var unit_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
	var enemy_unit_id = _fire_overwatch_enemy_unit_id
	if enemy_unit_id.is_empty():
		enemy_unit_id = _overwatch_moved_unit_id
	var enemy_unit_name = get_unit(enemy_unit_id).get("meta", {}).get("name", enemy_unit_id)

	# Use the stratagem via StratagemManager (deducts CP, records usage)
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var strat_result = strat_manager.use_stratagem(player, "fire_overwatch", unit_id)
		if not strat_result.success:
			return create_result(false, [], "Failed to use Fire Overwatch: %s" % strat_result.get("error", "unknown"))

	log_phase_message("Player %d uses FIRE OVERWATCH — %s shoots at moving %s!" % [player, unit_name, enemy_unit_name])
	DebugLogger.info(str("MovementPhase: Fire Overwatch activated — %s (Player %d) shooting at %s" % [unit_name, player, enemy_unit_name]))

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
	# Issue #329: forward action.payload.rng_seed
	var mov_ow_seed: int = action.get("payload", {}).get("rng_seed", -1)
	var ow_shooting_result = _resolve_overwatch_shooting(unit_id, enemy_unit_id, player, mov_ow_seed)

	# P1-59: Clear out-of-phase flag after overwatch resolves
	if strat_manager:
		strat_manager.set_out_of_phase_active(false)

	# Log detailed overwatch roll results to GameEventLog
	if game_event_log:
		_log_overwatch_results_to_game_log(game_event_log, ow_shooting_result, unit_name, enemy_unit_name, player)

	# Clear Overwatch state
	_awaiting_fire_overwatch = false
	_fire_overwatch_player = 0
	_fire_overwatch_enemy_unit_id = ""
	_fire_overwatch_eligible_units = []
	_awaiting_overwatch_decision = false
	_overwatch_moved_unit_id = ""

	emit_signal("overwatch_result", unit_id, enemy_unit_id, ow_shooting_result)

	# P2-88: If overwatch was triggered after Rapid Ingress, complete the phase now
	# (through the Codex: Orks (11e) movement_phase_end windows).
	var ri_end_changes: Array = []
	if _rapid_ingress_pending_phase_complete:
		_rapid_ingress_pending_phase_complete = false
		log_phase_message("Ending Movement Phase (after Rapid Ingress + Overwatch) - emitting phase_completed signal")
		ri_end_changes = _complete_movement_phase([]).get("changes", [])
		log_phase_message("=== END_MOVEMENT COMPLETE (post-Rapid Ingress + Overwatch) ===")

	# OA-8: Check for pending Krump and Run after overwatch used
	if _krump_and_run_pending_after_overwatch:
		_krump_and_run_pending_after_overwatch = false
		var fell_back_id = _krump_and_run_pending_fell_back_id
		_krump_and_run_pending_fell_back_id = ""
		DebugLogger.info("MovementPhase: OA-8 Checking deferred Krump and Run after Fire Overwatch used")
		# game_state_snapshot is now updated with fall-back positions
		var kar_result = _check_krump_and_run_opportunity(fell_back_id)
		if kar_result.triggered:
			var kar_extra_result = create_result(true, ow_shooting_result.get("diffs", []))
			kar_extra_result["fire_overwatch_used"] = true
			kar_extra_result["fire_overwatch_unit_id"] = unit_id
			kar_extra_result["fire_overwatch_target_id"] = enemy_unit_id
			kar_extra_result["fire_overwatch_shooting_result"] = ow_shooting_result
			if ow_shooting_result.has("dice"):
				kar_extra_result["dice"] = ow_shooting_result.dice
			if ow_shooting_result.has("log_text"):
				kar_extra_result["log_text"] = ow_shooting_result.log_text
			kar_extra_result.merge(kar_result.result_extra)
			return kar_extra_result

	# OA-42: Check for pending Scatter! after overwatch used
	if _scatter_pending_after_overwatch:
		_scatter_pending_after_overwatch = false
		var trigger_id = _scatter_pending_trigger_id
		_scatter_pending_trigger_id = ""
		_scatter_pending_changes = []
		_scatter_pending_dice = []
		DebugLogger.info("MovementPhase: OA-42 Checking deferred Scatter! after Fire Overwatch used")
		var sct_result = _check_scatter_opportunity(trigger_id)
		if sct_result.triggered:
			var sct_extra_result = create_result(true, ow_shooting_result.get("diffs", []))
			sct_extra_result["fire_overwatch_used"] = true
			sct_extra_result["fire_overwatch_unit_id"] = unit_id
			sct_extra_result["fire_overwatch_target_id"] = enemy_unit_id
			sct_extra_result["fire_overwatch_shooting_result"] = ow_shooting_result
			if ow_shooting_result.has("dice"):
				sct_extra_result["dice"] = ow_shooting_result.dice
			if ow_shooting_result.has("log_text"):
				sct_extra_result["log_text"] = ow_shooting_result.log_text
			sct_extra_result.merge(sct_result.result_extra)
			return sct_extra_result

	var result = create_result(true, ow_shooting_result.get("diffs", []))
	result["fire_overwatch_used"] = true
	result["fire_overwatch_unit_id"] = unit_id
	result["fire_overwatch_target_id"] = enemy_unit_id
	result["fire_overwatch_shooting_result"] = ow_shooting_result
	if ow_shooting_result.has("dice"):
		result["dice"] = ow_shooting_result.dice
	if ow_shooting_result.has("log_text"):
		result["log_text"] = ow_shooting_result.log_text
	return _ork11e_with_enemy_ended_move(_ork11e_merge_diffs(result, ri_end_changes))

func _process_decline_fire_overwatch(action: Dictionary) -> Dictionary:
	var player = action.get("player", _fire_overwatch_player)
	log_phase_message("Player %d declined FIRE OVERWATCH" % player)
	DebugLogger.info(str("MovementPhase: Fire Overwatch DECLINED by Player %d" % player))

	# Clear Overwatch state
	_awaiting_fire_overwatch = false
	_fire_overwatch_player = 0
	_fire_overwatch_enemy_unit_id = ""
	_fire_overwatch_eligible_units = []
	_awaiting_overwatch_decision = false
	_overwatch_moved_unit_id = ""

	# P2-88: If overwatch was triggered after Rapid Ingress, complete the phase now
	# (through the Codex: Orks (11e) movement_phase_end windows).
	var ri_end_changes: Array = []
	if _rapid_ingress_pending_phase_complete:
		_rapid_ingress_pending_phase_complete = false
		log_phase_message("Ending Movement Phase (after Rapid Ingress + Overwatch declined) - emitting phase_completed signal")
		ri_end_changes = _complete_movement_phase([]).get("changes", [])
		log_phase_message("=== END_MOVEMENT COMPLETE (post-Rapid Ingress + Overwatch declined) ===")

	# OA-8: Check for pending Krump and Run after overwatch declined
	if _krump_and_run_pending_after_overwatch:
		_krump_and_run_pending_after_overwatch = false
		var fell_back_id = _krump_and_run_pending_fell_back_id
		_krump_and_run_pending_fell_back_id = ""
		DebugLogger.info("MovementPhase: OA-8 Checking deferred Krump and Run after Fire Overwatch declined")
		var kar_result = _check_krump_and_run_opportunity(fell_back_id)
		if kar_result.triggered:
			var result = create_result(true, [])
			result.merge(kar_result.result_extra)
			return result

	# OA-42: Check for pending Scatter! after overwatch declined
	if _scatter_pending_after_overwatch:
		_scatter_pending_after_overwatch = false
		var trigger_id = _scatter_pending_trigger_id
		_scatter_pending_trigger_id = ""
		_scatter_pending_changes = []
		_scatter_pending_dice = []
		DebugLogger.info("MovementPhase: OA-42 Checking deferred Scatter! after Fire Overwatch declined")
		var sct_result = _check_scatter_opportunity(trigger_id)
		if sct_result.triggered:
			var result = create_result(true, [])
			result.merge(sct_result.result_extra)
			return result

	return _ork11e_with_enemy_ended_move(create_result(true, ri_end_changes))

# ============================================================================
# BOMB SQUIGS (P2-25)
# ============================================================================
# "Once per battle, after this unit ends a Normal move, you can select one enemy
# unit within 12\" of and visible to this unit and roll one D6: on a 3+, that
# enemy unit suffers D3 mortal wounds."


# ============================================================================
# OA-25: DEFF FROM ABOVE (Deffkoptas)
# ============================================================================
# "Each time this unit ends a Normal move, you can select one enemy unit it moved
# over during that move and roll one D6 for each model in this unit: for each 4+,
# that enemy unit suffers 1 mortal wound."


func _get_units_moved_over(unit_id: String, move_data: Dictionary) -> Array:
	"""Get enemy units whose bases were crossed during a unit's movement path.
	Returns array of { target_unit_id: String, target_name: String }.
	Uses the same path sampling approach as _path_crosses_enemy_bases but returns which units."""
	var current_player = get_current_player()
	var units = game_state_snapshot.get("units", {})
	var moving_unit = units.get(unit_id, {})
	if moving_unit.is_empty():
		return []

	# Get a reference model for overlap detection
	var reference_model = {}
	for model in moving_unit.get("models", []):
		if model.get("alive", true):
			reference_model = model.duplicate()
			break
	if reference_model.is_empty():
		return []

	# Collect all movement path segments from model_moves
	var path_segments = []
	for model_move in move_data.get("model_moves", []):
		var from_pos = model_move.get("from")
		var dest_pos = model_move.get("dest")
		if from_pos != null and dest_pos != null:
			path_segments.append({"from": from_pos, "dest": dest_pos})

	if path_segments.is_empty():
		return []

	# Check each enemy unit to see if any model's path crossed their bases
	var crossed_units = {}  # unit_id -> unit_name (deduplicate)

	for segment in path_segments:
		var from = segment.from
		var to = segment.dest

		# Sample points along the path (approximately every 10 pixels)
		var path_length = from.distance_to(to)
		var num_samples = max(2, int(path_length / 10.0))

		for i in range(num_samples + 1):
			var t = float(i) / float(num_samples)
			var sample_pos = from.lerp(to, t)

			# Create a temporary model at this position
			var model_at_pos = reference_model.duplicate()
			model_at_pos["position"] = sample_pos

			# Check against all enemy units
			for enemy_unit_id in units:
				if crossed_units.has(enemy_unit_id):
					continue  # Already found this unit
				var enemy_unit = units[enemy_unit_id]
				if int(enemy_unit.get("owner", 0)) == current_player:
					continue  # Skip friendly units
				if enemy_unit_id == unit_id:
					continue  # Skip self

				var has_alive = false
				for enemy_model in enemy_unit.get("models", []):
					if not enemy_model.get("alive", true):
						continue
					has_alive = true
					var enemy_pos = _get_model_position(enemy_model)
					if enemy_pos and Measurement.models_overlap(model_at_pos, enemy_model):
						var enemy_name = enemy_unit.get("meta", {}).get("name", enemy_unit_id)
						crossed_units[enemy_unit_id] = enemy_name
						break

				if not has_alive:
					continue

	# Convert to array format
	var result = []
	for eid in crossed_units:
		result.append({
			"target_unit_id": eid,
			"target_name": crossed_units[eid]
		})

	return result


func _validate_apply_pivot_cost(action: Dictionary) -> Dictionary:
	"""Validate APPLY_PIVOT_COST action — pivot cost deduction for non-round base models."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["No active move for unit"]}

	var move_data = active_moves[unit_id]

	# Already applied this move
	if move_data.get("pivot_cost_applied", false):
		return {"valid": false, "errors": ["Pivot cost already applied for this move"]}

	# No pivot cost for this unit
	var pivot_value = move_data.get("pivot_value", 0.0)
	if pivot_value <= 0:
		return {"valid": false, "errors": ["Unit has no pivot cost"]}

	return {"valid": true, "errors": []}

func _process_apply_pivot_cost(action: Dictionary) -> Dictionary:
	"""Apply pivot cost to a unit's movement — deducts pivot value from effective movement cap.
	10e Core Rules Update: non-round base costs subtracted from movement on first pivot."""
	var unit_id = action.get("actor_unit_id", "")
	var move_data = active_moves[unit_id]
	var pivot_value = move_data.get("pivot_value", 0.0)

	move_data["pivot_cost_applied"] = true

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var effective_cap = move_data.move_cap_inches - pivot_value

	log_phase_message("PIVOT COST: %s — %.0f\" deducted from movement (effective cap: %.1f\")" % [unit_name, pivot_value, effective_cap])
	DebugLogger.info(str("MovementPhase: PIVOT COST applied for %s: %.0f\" (cap %.1f\" → effective %.1f\")" % [unit_name, pivot_value, move_data.move_cap_inches, effective_cap]))

	return create_result(true, [], "", {
		"pivot_cost_applied": true,
		"pivot_value": pivot_value,
		"effective_move_cap": effective_cap
	})


func _continue_end_movement_rapid_ingress(changes: Array) -> Dictionary:
	"""END_MOVEMENT tail: checks for Rapid Ingress, then completes the phase."""
	var current_player = get_current_player()

	# T4-7: Check for Rapid Ingress opportunity for the non-active player
	var defending_player = 2 if current_player == 1 else 1
	var battle_round = GameState.get_battle_round()

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager and battle_round >= 2:
		var strat_check = strat_manager.can_use_stratagem(defending_player, "rapid_ingress")
		if strat_check.can_use:
			var ri_eligible = _get_rapid_ingress_eligible_units(defending_player)
			if not ri_eligible.is_empty():
				_awaiting_rapid_ingress = true
				_rapid_ingress_player = defending_player
				_rapid_ingress_eligible_units = ri_eligible
				log_phase_message("RAPID INGRESS available for Player %d (%d eligible reserve units)" % [defending_player, ri_eligible.size()])
				DebugLogger.info(str("MovementPhase: Rapid Ingress opportunity — Player %d has %d eligible units in reserves" % [defending_player, ri_eligible.size()]))

				emit_signal("rapid_ingress_opportunity", defending_player, ri_eligible)

				var result = create_result(true, changes)
				result["trigger_rapid_ingress"] = true
				result["awaiting_rapid_ingress"] = true
				result["rapid_ingress_player"] = defending_player
				result["rapid_ingress_eligible_units"] = ri_eligible
				return result

	log_phase_message("Ending Movement Phase (post-abilities) - emitting phase_completed signal")
	log_phase_message("Ending Movement Phase - emitting phase_completed signal")
	var end_result := _complete_movement_phase(changes)
	log_phase_message("=== END_MOVEMENT COMPLETE ===")
	return end_result


func _get_unit_center(unit: Dictionary) -> Variant:
	"""Get the center position of a unit's alive models. Returns null if no positioned models."""
	var positions = []
	for model in unit.get("models", []):
		if model.get("alive", true) and model.get("position", null) != null:
			var pos = model.position
			if pos is Vector2:
				positions.append(pos)
			elif pos is Dictionary and pos.has("x") and pos.has("y"):
				positions.append(Vector2(pos.x, pos.y))

	if positions.is_empty():
		return null

	var center = Vector2.ZERO
	for p in positions:
		center += p
	return center / positions.size()


# ============================================================================
# RAPID INGRESS STRATAGEM (T4-7)
# ============================================================================

func _get_rapid_ingress_eligible_units(player: int) -> Array:
	"""Get reserve units eligible for Rapid Ingress for the given player.
	Returns array of { unit_id: String, unit_name: String, reserve_type: String }.
	Attached characters are excluded — they arrive with their bodyguard."""
	var eligible = []
	var battle_round = GameState.get_battle_round()

	var reserves = GameState.get_reserves_for_player(player)
	for unit_id in reserves:
		var unit = get_unit(unit_id)
		if unit.is_empty():
			continue

		# Skip attached characters — they arrive with their bodyguard.
		# #362: Dictionary.get(key, default) returns the default ONLY when the key
		# is missing; if the key exists with value null (which is how this project
		# stores "not attached"), it returns null. Compare for null AND empty.
		var attached_to = unit.get("attached_to", "")
		if attached_to != null and attached_to != "":
			continue

		var reserve_type = unit.get("reserve_type", "strategic_reserves")

		if GameConstants.edition >= 11:
			# 15.07 TARGET: "One friendly unit that is in strategic reserves
			# (excluding AIRCRAFT)."
			if RulesEngine.unit_has_keyword(unit, "AIRCRAFT"):
				log_phase_message("[11e 15.07] %s is AIRCRAFT — not offered RAPID INGRESS" % unit_id)
				continue
			# 20.04 ELIGIBLE IF: excluding units embarked within TRANSPORTS that
			# are themselves in strategic reserves (they arrive with it).
			if unit.get("embarked_in", null) != null:
				continue
			# Battle-shock: its controlling player cannot target that unit with
			# stratagems (a repositioned unit stays battle-shocked, 20.02).
			if unit.get("flags", {}).get("battle_shocked", false):
				log_phase_message("[11e 15.07] %s is battle-shocked — not offered RAPID INGRESS" % unit_id)
				continue

		# Rapid Ingress restriction: cannot arrive in a battle round the unit
		# normally wouldn't be able to. Strategic reserves & deep strike both
		# require battle round >= 2, which we already check before calling this.
		# (Special rules allowing Round 1 arrival are not yet implemented.)

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		# Show attached characters in the name
		var attachment_data = unit.get("attachment_data", {})
		var attached_chars = attachment_data.get("attached_characters", [])
		for char_id in attached_chars:
			var char_unit = get_unit(char_id)
			if char_unit.get("status", 0) == GameStateData.UnitStatus.IN_RESERVES:
				unit_name += " + " + char_unit.get("meta", {}).get("name", char_id)
		eligible.append({
			"unit_id": unit_id,
			"unit_name": unit_name,
			"reserve_type": reserve_type
		})

	return eligible

func _validate_use_rapid_ingress(action: Dictionary) -> Dictionary:
	var errors = []

	if not _awaiting_rapid_ingress:
		errors.append("Not awaiting Rapid Ingress decision")
		return {"valid": false, "errors": errors}

	var unit_id = _rapid_ingress_action_unit_id(action)
	if unit_id.is_empty():
		errors.append("No unit specified for Rapid Ingress")
		return {"valid": false, "errors": errors}

	var player = action.get("player", _rapid_ingress_player)

	# Validate through StratagemManager
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var check = strat_manager.can_use_stratagem(player, "rapid_ingress")
		if not check.can_use:
			errors.append(check.reason)
			return {"valid": false, "errors": errors}

	# Validate the unit is in reserves and belongs to the player
	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
		return {"valid": false, "errors": errors}

	if int(unit.get("owner", 0)) != player:
		errors.append("Unit does not belong to player %d" % player)
		return {"valid": false, "errors": errors}

	if unit.get("status", 0) != GameStateData.UnitStatus.IN_RESERVES:
		errors.append("Unit is not in reserves")
		return {"valid": false, "errors": errors}

	# 11e 15.07: only an offered unit (strategic reserves, not AIRCRAFT, not
	# battle-shocked) — re-checked here, on the peer that runs the phase.
	if GameConstants.edition >= 11:
		var offered := false
		for row in _rapid_ingress_eligible_units:
			if str(row.get("unit_id", "")) == unit_id:
				offered = true
				break
		if not offered:
			errors.append("RAPID INGRESS cannot target %s (15.07: one friendly unit in strategic reserves, excluding AIRCRAFT)" % unit_id)
			return {"valid": false, "errors": errors}

	return {"valid": true, "errors": []}

func _validate_decline_rapid_ingress(action: Dictionary) -> Dictionary:
	if not _awaiting_rapid_ingress:
		return {"valid": false, "errors": ["Not awaiting Rapid Ingress decision"]}
	return {"valid": true, "errors": []}

func _validate_place_rapid_ingress_reinforcement(action: Dictionary) -> Dictionary:
	"""Validate placing a reserve unit via Rapid Ingress.
	Same rules as normal reinforcement placement but for the non-active player."""
	var errors = []

	if _rapid_ingress_unit_id.is_empty():
		errors.append("No Rapid Ingress unit selected — use USE_RAPID_INGRESS first")
		return {"valid": false, "errors": errors}

	var required_fields = ["unit_id", "model_positions"]
	for field in required_fields:
		if not action.has(field):
			errors.append("Missing required field: " + field)

	if errors.size() > 0:
		return {"valid": false, "errors": errors}

	var unit_id = action.unit_id
	if unit_id != _rapid_ingress_unit_id:
		errors.append("Unit %s is not the selected Rapid Ingress unit (%s)" % [unit_id, _rapid_ingress_unit_id])
		return {"valid": false, "errors": errors}

	var model_positions = action.model_positions

	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
		return {"valid": false, "errors": errors}

	if unit.get("status", 0) != GameStateData.UnitStatus.IN_RESERVES:
		errors.append("Unit is not in reserves: " + unit_id)
		return {"valid": false, "errors": errors}

	# The player performing Rapid Ingress is the non-active (defending) player
	var player = _rapid_ingress_player
	if unit.get("owner", 0) != player:
		errors.append("Unit does not belong to player %d" % player)
		return {"valid": false, "errors": errors}

	var battle_round = GameState.get_battle_round()
	if battle_round < 2:
		errors.append("Reserves cannot arrive until Battle Round 2 (currently Round %d)" % battle_round)
		return {"valid": false, "errors": errors}

	var reserve_type = unit.get("reserve_type", "strategic_reserves")

	# P2-80: Support placement_type override for Rapid Ingress too
	var placement_type = action.get("placement_type", reserve_type)
	if placement_type == "deep_strike" and reserve_type == "strategic_reserves":
		if not GameState.unit_has_deep_strike(unit_id):
			errors.append("Unit does not have Deep Strike ability — cannot use Deep Strike placement rules")
			return {"valid": false, "errors": errors}
		DebugLogger.info(str("MovementPhase: P2-80 — Rapid Ingress unit %s using Deep Strike placement rules (from Strategic Reserves)" % unit.get("meta", {}).get("name", unit_id)))

	# The whole arriving set-up: bodyguard + every attached CHARACTER coming in
	# with it (11e 24.10 — one Attached unit, set up together and validated together).
	var arrival_groups = _collect_arrival_groups(unit, unit_id, model_positions if model_positions is Array else [], action.get("model_rotations", []), action)

	# Set-up overlap gate (03.02) — same as normal reinforcement placement:
	# Rapid Ingress models may not be set up overlapping existing models,
	# each other, or walls.
	if model_positions is Array:
		var setup_overlap = _validate_reinforcement_setup_overlaps(arrival_groups)
		if not setup_overlap.valid:
			return setup_overlap

	# WP-M4b TELEPORT HOMER (Codex: Space Marines 11e, Terminator Squad): a set-up
	# wholly within 3" of the unit's token uses it — "within 3" of that token and
	# not within 8" of an enemy unit" replaces the strategic reserves edge rules.
	var sm11e_homer: bool = model_positions is Array and load("res://scripts/codex/space_marines/SMAbilitiesB.gd").homer_setup_ok(unit_id, model_positions)
	if sm11e_homer:
		log_phase_message("Teleport Homer: %s is set up within 3\" of its token (RAPID INGRESS -1 CP)" % unit_id)
	# Validate model positions — same rules as normal reinforcement placement
	if model_positions is Array:
		var board_width = GameState.state.board.size.width
		var board_height = GameState.state.board.size.height
		var px_per_inch = 40.0

		for g in arrival_groups:
			var g_unit_id = str(g["unit_id"])
			var g_models = g["unit"].get("models", [])
			var g_label = "" if g_unit_id == unit_id else "%s " % g["unit"].get("meta", {}).get("name", g_unit_id)
			for i in range(g["positions"].size()):
				var pos = _reinforcement_pos_to_vec2(g["positions"][i])
				if pos == null:
					continue

				var pos_inches_x = pos.x / px_per_inch
				var pos_inches_y = pos.y / px_per_inch

				# Must be on the board
				if pos_inches_x < 0 or pos_inches_x > board_width or pos_inches_y < 0 or pos_inches_y > board_height:
					errors.append("%sModel %d: position is off the board" % [g_label, i])
					continue

				# Must be >9" from all enemy models (edge-to-edge)
				var model_data = g_models[i] if i < g_models.size() else {}
				var model_base_mm = model_data.get("base_mm", 32)
				var model_radius_inches = (model_base_mm / 2.0) / 25.4

				# For Rapid Ingress, "enemies" are the active player's models
				# get_enemy_model_positions(player) returns models NOT belonging to player
				# 11e (20.04 Ingress): set up >8" from enemies (vs 10e's >9").
				var min_enemy_sep = GameConstants.reinforcement_min_enemy_distance_inches()
				var enemy_positions = GameState.get_enemy_model_positions(player)
				for enemy in enemy_positions:
					var enemy_pos_px = Vector2(enemy.x, enemy.y)
					var enemy_radius_inches = (enemy.base_mm / 2.0) / 25.4
					var dist_px = pos.distance_to(enemy_pos_px)
					var dist_inches = dist_px / px_per_inch
					var edge_dist = dist_inches - model_radius_inches - enemy_radius_inches
					if edge_dist < min_enemy_sep:
						errors.append("%sModel %d: must be >%.0f\" from enemy models (currently %.1f\")" % [g_label, i, min_enemy_sep, edge_dist])
						break

				# Strategic Reserves: must be within 6" of a battlefield edge
				# P2-80: Use placement_type for validation
				if placement_type == "strategic_reserves" and not sm11e_homer:  # WP-M4b: not when the Teleport Homer set-up applies
					# 20.04 (and 10e's identical wording): set up WHOLLY within 6"
					# of a battlefield edge — the whole base, not the centre dot.
					var dist_to_left = pos_inches_x
					var dist_to_right = board_width - pos_inches_x
					var dist_to_top = pos_inches_y
					var dist_to_bottom = board_height - pos_inches_y
					var min_edge_dist = min(dist_to_left, dist_to_right, dist_to_top, dist_to_bottom)

					if not _wholly_within_setup_distance(pos, model_data, g["rotations"], i, board_width, board_height):
						errors.append("%sModel %d: Strategic Reserves must be set up wholly within 6\" of a battlefield edge (base reaches %.1f\")" % [g_label, i, min_edge_dist + model_radius_inches])

					# 20.04: before the THIRD battle round, no model may be set up
					# within the opponent's deployment zone.
					if GameState.ingress_opponent_dz_ban_applies(battle_round, false):
						# For Rapid Ingress, "opponent" is the active player —
						# the ingressing player is the one holding the stratagem.
						var dz_probe = _dz_probe_model(model_data, pos, g["rotations"], i)
						if Measurement.model_overlaps_polygon(dz_probe, GameState.get_deployment_zone_poly_px(get_current_player())):
							errors.append("%sModel %d: Strategic Reserves cannot arrive in the opponent's deployment zone before battle round 3" % [g_label, i])

				# Omni-scramblers: cannot be set up within 12" of enemy units with Omni-scramblers
				var omni_positions = GameState.get_omni_scrambler_positions(player)
				for omni in omni_positions:
					var omni_pos_px = Vector2(omni.x, omni.y)
					var omni_radius_inches = (omni.base_mm / 2.0) / 25.4
					var dist_px = pos.distance_to(omni_pos_px)
					var dist_inches = dist_px / px_per_inch
					var edge_dist = dist_inches - model_radius_inches - omni_radius_inches
					if edge_dist < 12.0:
						errors.append("%sModel %d: cannot be set up within 12\" of enemy Omni-scramblers (%s) (currently %.1f\")" % [g_label, i, omni.get("unit_name", "unknown"), edge_dist])
						break

	# WP-M4a TELEPORT HOMER: a Rapid Ingress that uses the token sets the unit up within 3" of it.
	if errors.is_empty() and model_positions is Array:
		errors.append_array(_sm11e_abilities_a().homer_setup_errors(unit_id, model_positions))

	# Check unit coherency
	if errors.is_empty():
		var final_models = []
		var unit_models = unit.get("models", [])
		for i in range(model_positions.size()):
			if model_positions[i] == null:
				continue
			if i >= unit_models.size():
				break
			if not unit_models[i].get("alive", true):
				continue
			var model_at_pos = unit_models[i].duplicate()
			model_at_pos["position"] = model_positions[i]
			final_models.append(model_at_pos)

		var coherency_result = _check_models_coherency(final_models)
		if not coherency_result.valid:
			errors.append_array(coherency_result.errors)

	return {"valid": errors.size() == 0, "errors": errors}

## The unit a USE_RAPID_INGRESS names: action.unit_id, else payload.unit_id /
## actor_unit_id (the shape MovementController's dialog used to send).
func _rapid_ingress_action_unit_id(action: Dictionary) -> String:
	var uid := str(action.get("unit_id", ""))
	if uid == "":
		uid = str(action.get("payload", {}).get("unit_id", action.get("actor_unit_id", "")))
	return uid

func _process_use_rapid_ingress(action: Dictionary) -> Dictionary:
	var unit_id = _rapid_ingress_action_unit_id(action)
	var player = action.get("player", _rapid_ingress_player)
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	# Use the stratagem via StratagemManager (deducts CP, records usage)
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var strat_result = strat_manager.use_stratagem(player, "rapid_ingress", unit_id)
		if not strat_result.success:
			return create_result(false, [], "Failed to use Rapid Ingress: %s" % strat_result.get("error", "unknown"))

	log_phase_message("Player %d uses RAPID INGRESS — %s selected to arrive from reserves!" % [player, unit_name])
	DebugLogger.info(str("MovementPhase: Rapid Ingress activated — %s (Player %d) arriving from reserves" % [unit_name, player]))

	# Mark the selected unit for placement — the player still needs to choose positions
	_rapid_ingress_unit_id = unit_id

	# Clear the awaiting state for the selection step (now awaiting placement)
	_awaiting_rapid_ingress = false
	_rapid_ingress_eligible_units = []

	var result = create_result(true, [])
	result["rapid_ingress_used"] = true
	result["rapid_ingress_unit_id"] = unit_id
	result["rapid_ingress_player"] = player
	return result

func _process_decline_rapid_ingress(action: Dictionary) -> Dictionary:
	var player = action.get("player", _rapid_ingress_player)
	log_phase_message("Player %d declined RAPID INGRESS" % player)
	DebugLogger.info(str("MovementPhase: Rapid Ingress DECLINED by Player %d" % player))

	# Clear Rapid Ingress state
	_awaiting_rapid_ingress = false
	_rapid_ingress_player = 0
	_rapid_ingress_eligible_units = []
	_rapid_ingress_unit_id = ""

	# Now actually end the movement phase
	log_phase_message("Ending Movement Phase (after Rapid Ingress declined) - emitting phase_completed signal")
	var end_result := _complete_movement_phase([])
	log_phase_message("=== END_MOVEMENT COMPLETE (post-Rapid Ingress decline) ===")
	return end_result

func _process_place_rapid_ingress_reinforcement(action: Dictionary) -> Dictionary:
	"""Process placing a reserve unit via Rapid Ingress onto the battlefield."""
	var unit_id = action.unit_id
	var model_positions = action.model_positions
	var model_rotations = action.get("model_rotations", [])
	var player = _rapid_ingress_player
	var changes = []
	# WP-M4b TELEPORT HOMER (Codex: Space Marines 11e): a set-up within 3" of the
	# token uses it — -1 CP (refunded) and the token is removed (before the move).
	changes.append_array(load("res://scripts/codex/space_marines/SMAbilitiesB.gd").on_rapid_ingress_setup(str(unit_id), model_positions if model_positions is Array else []))

	# Update model positions
	for i in range(model_positions.size()):
		var pos = model_positions[i]
		if pos != null:
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [unit_id, i],
				"value": {"x": pos.x, "y": pos.y}
			})
			if i < model_rotations.size() and model_rotations[i] != null:
				changes.append({
					"op": "set",
					"path": "units.%s.models.%d.rotation" % [unit_id, i],
					"value": model_rotations[i]
				})

	# Update unit status from IN_RESERVES to DEPLOYED
	changes.append({
		"op": "set",
		"path": "units.%s.status" % unit_id,
		"value": GameStateData.UnitStatus.DEPLOYED
	})

	# OA-23: Track the battle round this unit arrived from reserves (for Plummeting Descent)
	changes.append({
		"op": "set",
		"path": "units.%s.arrived_from_reserves_turn" % unit_id,
		"value": GameState.get_battle_round()
	})

	# ISS-060 step 2 (11e 20.04): the arrival is an INGRESS MOVE — the
	# template's AFTER effects apply (arrived_from_reserves +
	# no-other-moves-until-the-next-Charge-phase, so the unit CAN charge).
	if GameConstants.edition >= 11:
		changes.append_array(MoveTypes.get_type("ingress").after_moving_effects(unit_id, {}))
		log_phase_message("[11e] %s arrived via ingress move (may charge; no further moves this phase)" % unit_id)

	# Deploy attached characters that are also in reserves (same logic as PLACE_REINFORCEMENT):
	# the leader's model comes from the placement UI when the player positioned it,
	# and is auto-placed clear of the squad otherwise.
	var unit = get_unit(unit_id)
	var attachment_data = unit.get("attachment_data", {})
	var attached_chars = attachment_data.get("attached_characters", [])
	var char_model_positions = action.get("character_model_positions", {})
	var char_model_rotations = action.get("character_model_rotations", {})
	var arrival_footprint = _arrival_footprint(unit, model_positions, model_rotations)

	for char_id in attached_chars:
		var char_unit = get_unit(char_id)
		if char_unit.get("status", 0) != GameStateData.UnitStatus.IN_RESERVES:
			continue
		var char_positions = char_model_positions.get(char_id, [])
		var char_rotations = char_model_rotations.get(char_id, [])
		var char_models = char_unit.get("models", [])
		for ci in range(char_models.size()):
			var char_pos = null
			if ci < char_positions.size():
				char_pos = _reinforcement_pos_to_vec2(char_positions[ci])
			var char_rot = null
			if ci < char_rotations.size() and char_rotations[ci] != null:
				char_rot = float(char_rotations[ci])
			if char_pos == null:
				char_pos = _auto_place_attached_character_model(char_models[ci], char_unit, model_positions, arrival_footprint)
			if char_pos != null:
				changes.append({
					"op": "set",
					"path": "units.%s.models.%d.position" % [char_id, ci],
					"value": {"x": char_pos.x, "y": char_pos.y}
				})
				if char_rot != null:
					changes.append({
						"op": "set",
						"path": "units.%s.models.%d.rotation" % [char_id, ci],
						"value": char_rot
					})
				var footprint_model = char_models[ci].duplicate()
				footprint_model["position"] = char_pos
				if char_rot != null:
					footprint_model["rotation"] = char_rot
				arrival_footprint.append(footprint_model)
		changes.append({
			"op": "set",
			"path": "units.%s.status" % char_id,
			"value": GameStateData.UnitStatus.DEPLOYED
		})
		var char_name = char_unit.get("meta", {}).get("name", char_id)
		log_phase_message("Attached character %s arrived via Rapid Ingress with bodyguard" % char_name)

	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)

	# Update local snapshot
	if game_state_snapshot.has("units") and game_state_snapshot.units.has(unit_id):
		game_state_snapshot.units[unit_id]["status"] = GameStateData.UnitStatus.DEPLOYED
	for char_id in attached_chars:
		if game_state_snapshot.has("units") and game_state_snapshot.units.has(char_id):
			game_state_snapshot.units[char_id]["status"] = GameStateData.UnitStatus.DEPLOYED

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var reserve_type = unit.get("reserve_type", "strategic_reserves")
	var type_label = "Deep Strike" if reserve_type == "deep_strike" else "Strategic Reserves"
	log_phase_message("Rapid Ingress reinforcement arrived: %s via %s (Player %d)" % [unit_name, type_label, player])

	# Clear Rapid Ingress state
	_rapid_ingress_unit_id = ""
	_rapid_ingress_player = 0

	# WP-M4a TELEPORT HOMER: the token this set-up used is removed.
	var sm_homer_ri: Array = _sm11e_abilities_a().on_reinforcement_set_up(unit_id)
	if not sm_homer_ri.is_empty():
		PhaseManager.apply_state_changes(sm_homer_ri)
		changes.append_array(sm_homer_ri)

	# P2-88: Check for Fire Overwatch opportunity after Rapid Ingress unit is set up
	# Balance Dataslate timing: "just after an enemy unit is set up"
	var ow_result = _check_fire_overwatch_opportunity(unit_id, "rapid ingress set up")
	if ow_result.triggered:
		# Overwatch triggered — don't end movement phase yet; it will be ended after
		# overwatch resolves (the use/decline handler will need to complete the phase)
		_rapid_ingress_pending_phase_complete = true
		var result = create_result(true, changes)
		result.merge(ow_result.result_extra)
		return result

	# Now actually end the movement phase
	log_phase_message("Ending Movement Phase (after Rapid Ingress placement) - emitting phase_completed signal")
	var end_result := _complete_movement_phase(changes)
	log_phase_message("=== END_MOVEMENT COMPLETE (post-Rapid Ingress) ===")
	return end_result

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

	log_phase_message("FIRE OVERWATCH result: %s fired at %s — %s" % [
		shooting_unit.get("meta", {}).get("name", shooting_unit_id),
		target_unit.get("meta", {}).get("name", target_unit_id),
		shoot_result.get("log_text", "no hits")
	])

	return shoot_result

func _log_overwatch_results_to_game_log(game_event_log, ow_result: Dictionary, shooter_name: String, target_name: String, player: int, own_unit_ids: Array = []) -> void:
	"""Log detailed overwatch roll results (hits, wounds, saves, casualties) to the GameEventLog.
	own_unit_ids: the shooting unit's components — their models lost to the
	unit's own [HAZARDOUS] check are not counted as casualties of the shot."""
	var dice_entries = ow_result.get("dice", [])
	var total_hits = 0
	var total_wounds = 0
	var total_failed_saves = 0
	var total_saved = 0

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
		elif context == "save" or context == "save_roll":
			# 10e blocks carry "fails"; the 11e allocation batch (05.03, the
			# defender's overlay → normalize_allocation_11e_dice) "failed".
			var fails = int(dice_entry.get("fails", dice_entry.get("failed", 0)))
			# The roll needed (after AP / an invulnerable save): 11e blocks
			# carry it as "threshold" ("sv" is the characteristic); 10e
			# blocks only have "sv".
			var sv = str(threshold) if str(threshold) != "" else dice_entry.get("sv", "")
			total_failed_saves += fails
			if fails == 0:
				total_saved += 1
			game_event_log.add_overwatch_entry("  Save roll: [%s] vs %s (%s)" % [
				rolls_str, str(sv), "failed!" if fails > 0 else "saved"])

	# LV2-G1: the overwatching unit's own [HAZARDOUS] roll(s), same wording as
	# the Shooting phase's Game Log line.
	for hi in range(dice_entries.size()):
		if str(dice_entries[hi].get("context", "")) == "hazardous_check":
			var haz_line: String = RulesEngine.hazard_game_log_line(dice_entries.slice(hi, hi + 2))
			if haz_line != "":
				game_event_log.add_overwatch_entry("  " + haz_line)

	# Count casualties from diffs (models set to alive=false)
	var total_casualties = 0
	for diff in ow_result.get("diffs", []):
		var path = diff.get("path", "")
		if path.ends_with(".alive") and diff.get("value") == false:
			if not own_unit_ids.is_empty() and path.begins_with("units.") and path.get_slice(".", 1) in own_unit_ids:
				continue
			total_casualties += 1

	# Log the final outcome summary
	if total_casualties > 0:
		game_event_log.add_overwatch_entry("  >>> %d model%s destroyed! <<<" % [
			total_casualties, "" if total_casualties == 1 else "s"])
	elif total_failed_saves > 0:
		game_event_log.add_overwatch_entry("  Result: %d failed save%s — damage dealt, no models destroyed" % [
			total_failed_saves, "" if total_failed_saves == 1 else "s"])
	elif total_wounds > 0:
		game_event_log.add_overwatch_entry("  Result: All wounds saved - no casualties")
	elif total_hits > 0:
		game_event_log.add_overwatch_entry("  Result: Hits failed to wound")
	else:
		game_event_log.add_overwatch_entry("  Result: No hits (only unmodified 6s hit)")


func _process_begin_fall_back(action: Dictionary) -> Dictionary:
	# Codex: Orks (11e) windows — the active player's unit_selected_to_move,
	# then the opponent's enemy_selected_to_fall_back (01.03.02) — before the
	# fall-back mode and move are set up.
	var stm := _ork11e_open_selected_to_move_windows(action, "fall_back")
	if stm.paused:
		return create_result(true, stm.diffs)
	return _ork11e_merge_diffs(_process_begin_fall_back_after_windows(action), stm.diffs)

## Everything that follows "selected to make a fall-back move" once the
## Codex: Orks (11e) windows have closed.
func _process_begin_fall_back_after_windows(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)
	var move_inches = get_unit_movement(unit)
	# ISS-061 (11e 21.03/24.17): "take to the skies" — an opt-in FLY
	# declaration per move (payload.take_to_skies): -2\" cap (0 with
	# HOVER); the mover ignores vertical distance and may move through
	# models and terrain (pathing consumers read took_to_skies).
	var took_to_skies := false
	if GameConstants.edition >= 11 and action.get("payload", {}).get("take_to_skies", false) \
			and "FLY" in GameState.get_unit(unit_id).get("meta", {}).get("keywords", []) \
			and not OrkAbilities11eScript.cannot_take_to_skies(unit_id):  # WP-O6 Madcap Artillery "grounded"
		took_to_skies = true
		var fly_mod = MoveType.take_to_skies_modifier(GameState.get_unit(unit_id))
		move_inches = max(0.0, move_inches + fly_mod)
		log_phase_message("[11e] %s takes to the skies: cap %s\" (%+.1f\"), may move through models and terrain" % [unit_id, str(move_inches), fly_mod])

	# ISS-073 (24.35): a SUPER-HEAVY WALKER may opt to grant all its models
	# the MOBILE keyword for this move (payload.shw_mobile_gamble) — letting
	# it move through dense terrain; at move end it rolls D6, on a 1 it is
	# battle-shocked. Recorded here, the D6 is rolled at CONFIRM.
	var shw_mobile: bool = GameConstants.edition >= 11 \
			and bool(action.get("payload", {}).get("shw_mobile_gamble", false)) \
			and UnitAbilities.is_super_heavy_walker(GameState.get_unit(unit_id))  # keyword or the 24.35 core ability
	# If unit already had staged moves (e.g. switching modes), reset visuals first
	_reset_staged_visuals_if_needed(unit_id)

	var pivot_value = get_pivot_value_for_unit(unit_id)
	active_moves[unit_id] = {
		"mode": "FALL_BACK",
		"took_to_skies": took_to_skies,
		"shw_mobile": shw_mobile,
		"mode_locked": false,  # Track if mode is confirmed
		"completed": false,  # Track if unit has completed movement
		"move_cap_inches": move_inches,
		"advance_roll": 0,  # Not used for Fall Back but kept for consistency
		"model_moves": [],
		"staged_moves": [],  # NEW: Temporary moves before confirmation
		"original_positions": {},  # NEW: Track starting positions for reset
		"original_rotations": {},  # Track starting rotations for reset
		"model_distances": {},  # NEW: Track per-model distances
		"dice_rolls": [],
		"battle_shocked": unit.get("status_effects", {}).get("battle_shocked", false),
		# Pivot tracking (10e Core Rules Update)
		"pivot_value": pivot_value,
		"pivot_cost_applied": false,
		# Multi-selection group movement support
		"group_moves": [],  # Track group movement operations
		"group_selection": [],  # Current multi-selected models
		"group_formation": {}  # Relative positions within group
	}
	
	log_phase_message("Beginning fall back for %s (M: %d\")" % [unit.get("meta", {}).get("name", unit_id), move_inches])

	# ISS-040 step 2 (11e 09.07): fall-back MODES via the template —
	# desperate escape is mandatory when battle-shocked and rolls one
	# hazard per model BEFORE moving (06.03); ordered retreat otherwise
	# (player may still opt into desperate escape via payload).
	var fb_hazard_changes: Array = []
	if GameConstants.edition >= 11:
		var fb_template = MoveTypes.get_type("fall_back")
		var fb_sel = fb_template.select_mode(unit_id, GameState.state)
		var fb_mode = str(action.get("payload", {}).get("fall_back_mode", fb_sel.mode))
		if not fb_mode in fb_sel.available:
			fb_mode = str(fb_sel.mode)
		active_moves[unit_id]["fall_back_mode"] = fb_mode
		log_phase_message("[11e] Fall-back mode for %s: %s (available: %s)" % [unit_id, fb_mode, str(fb_sel.available)])
		if fb_mode == "desperate_escape":
			var fb_ctx = fb_template.before_moving(unit_id, GameState.state, RulesEngine.make_rng(), {"mode": fb_mode})
			active_moves[unit_id]["desperate_escape_ctx"] = fb_ctx
			var hz = fb_ctx.get("hazard", {})
			log_phase_message("[11e] Desperate escape hazard rolls for %s: %s (%d failure(s))" % [unit_id, str(hz.get("rolls", [])), int(hz.get("failures", 0))])
			# Codex: Orks (11e) WHERE D'YA FINK YOU'RE GOING? forced this desperate
			# escape (FallBackMove.select_mode) — surface the hazard rolls, including
			# the extra MONSTER/VEHICLE rolls (FallBackMove.before_moving).
			if Ork11eMovement.where_dya_fink_forces_desperate_escape(unit_id, GameState.state):
				active_moves[unit_id]["fall_back_mode_forced_by"] = "WHERE D'YA FINK YOU'RE GOING?"
				_ork11e_log_where_dya_fink_hazards(unit_id, hz)
			# Codex: Adeptus Custodes CORNER THE QUARRY (CustodesAbilities.gd) forced it.
			elif _cus11e_abilities().corner_the_quarry_source(unit_id) != "":
				active_moves[unit_id]["fall_back_mode_forced_by"] = "Corner the Quarry"
				log_phase_message("[11e] Corner the Quarry: %s must use the desperate escape mode (hazard rolls %s)" % [unit_id, str(hz.get("rolls", []))])
			# WP-S4 SAVAGE FRENZY (Space Wolves, Wulfen) forced it.
			elif _sw11e_abilities().savage_frenzy_source(unit_id) != "":
				active_moves[unit_id]["fall_back_mode_forced_by"] = "Savage Frenzy"
				log_phase_message("[11e] Savage Frenzy: %s must use the desperate escape mode (hazard rolls %s)" % [unit_id, str(hz.get("rolls", []))])
			# 06.03: each failure destroys a model (3 MW each instead for
			# an all-MONSTER/VEHICLE unit, via the 06.02 allocation).
			if int(hz.get("failures", 0)) > 0:
				var mw = int(hz.get("mortal_wounds", 0))
				# Feel No Pain vs mortal wounds (incl. Aegis of the Emperor, WP-C3).
				mw = RulesEngine.mortal_wounds_after_fnp(unit, mw, null, [], false, "desperate_escape")
				var out = Allocation.apply_mortal_wounds_11e(unit, mw, CasualtyPreference.engine_auto_preference(unit, GameState.state))
				for ridx in out.remaining:
					var mi = int(ridx)
					fb_hazard_changes.append({"op": "set", "path": "units.%s.models.%d.current_wounds" % [unit_id, mi], "value": int(out.remaining[ridx])})
				for di in out.models_destroyed:
					fb_hazard_changes.append({"op": "set", "path": "units.%s.models.%d.alive" % [unit_id, int(di)], "value": false})
					fb_hazard_changes.append({"op": "set", "path": "units.%s.models.%d.current_wounds" % [unit_id, int(di)], "value": 0})

	# Emitted once the 11e fall-back mode is known, so the movement panel can
	# show it (Desperate Escape, and that it was forced — r3:F12).
	emit_signal("unit_move_begun", unit_id, "FALL_BACK")

	var begin_changes = [
		{
			"op": "set",
			"path": "units.%s.flags.fell_back" % unit_id,
			"value": true
		},
		{
			"op": "set",
			"path": "units.%s.flags.move_cap_inches" % unit_id,
			"value": move_inches
		},
		{
			"op": "set",
			"path": "units.%s.flags.movement_active" % unit_id,
			"value": true
		}
	]

	begin_changes.append_array(fb_hazard_changes)

	# P2-88: Check for Fire Overwatch at fall back move start
	# Balance Dataslate timing: "when an enemy unit starts a Fall Back move"
	var ow_result = _check_fire_overwatch_opportunity(unit_id, "fall back move start")
	if ow_result.triggered:
		var result = create_result(true, begin_changes)
		result.merge(ow_result.result_extra)
		return result

	return create_result(true, begin_changes)

func _process_set_model_dest(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var model_id = payload.get("model_id", "")
	var dest = payload.get("dest", [])
	var dest_vec = Vector2(dest[0], dest[1])
	
	var move_data = active_moves[unit_id]
	var model = _get_model_in_unit(unit_id, model_id)
	var current_pos = _get_model_position(model)
	
	# Calculate path and check for enemy crossing (Fall Back)
	var crosses_enemy = false
	if move_data.mode == "FALL_BACK":
		crosses_enemy = _path_crosses_enemy(current_pos, dest_vec, unit_id, model.get("base_mm", 32))
	
	# Add to model moves
	move_data.model_moves.append({
		"model_id": model_id,
		"from": current_pos,
		"dest": dest_vec,
		"crosses_enemy": crosses_enemy
	})
	
	var distance_inches = Measurement.distance_inches(current_pos, dest_vec)
	var model_rotation = model.get("rotation", 0.0)
	emit_signal("model_drop_committed", unit_id, model_id, dest_vec, model_rotation)

	return create_result(true, [
		{
			"op": "set",
			"path": "units.%s.models.%s.position" % [unit_id, _get_model_index(unit_id, model_id)],
			"value": {"x": dest_vec.x, "y": dest_vec.y}
		}
	])

func _process_stage_model_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var model_id = payload.get("model_id", "")
	var dest = payload.get("dest", [])
	var rotation = payload.get("rotation", 0.0)
	var dest_vec = Vector2(dest[0], dest[1])

	DebugLogger.info(str("[MovementPhase] Processing STAGE_MODEL_MOVE for model ", model_id, " to ", dest_vec))

	var move_data = active_moves[unit_id]
	# If model_source_unit_id is provided (attached character), look there first
	# to avoid model ID collisions (e.g. both units having "m1")
	var model_source_unit_id = payload.get("model_source_unit_id", "")
	var model = {}
	var model_actual_unit_id = unit_id
	if model_source_unit_id != "":
		model = _get_model_in_unit(model_source_unit_id, model_id)
		if not model.is_empty():
			model_actual_unit_id = model_source_unit_id
			DebugLogger.info(str("[MovementPhase] Processing stage move for attached character model %s (source unit %s)" % [model_id, model_source_unit_id]))
	if model.is_empty():
		model = _get_model_in_unit(unit_id, model_id)
	# Also check attached character units if model not found in the bodyguard unit
	if model.is_empty():
		var bodyguard = get_unit(unit_id)
		var attached_chars = bodyguard.get("attachment_data", {}).get("attached_characters", [])
		for char_id in attached_chars:
			model = _get_model_in_unit(char_id, model_id)
			if not model.is_empty():
				model_actual_unit_id = char_id
				DebugLogger.info(str("[MovementPhase] Processing stage move for attached character model %s (unit %s)" % [model_id, char_id]))
				break

	# Composite key to avoid collisions when bodyguard and character share model IDs (e.g. both "m1")
	var model_key = "%s:%s" % [model_actual_unit_id, model_id]

	# Get current position (may be staged)
	var current_pos = null
	for staged_move in move_data.staged_moves:
		if staged_move.model_id == model_id and staged_move.get("model_source_unit_id", unit_id) == model_actual_unit_id:
			current_pos = staged_move.dest
			break

	# If no staged position, use actual position
	if current_pos == null:
		current_pos = _get_model_position(model)
		# Store original position and rotation if this is the first move for this model
		if not move_data.original_positions.has(model_key):
			move_data.original_positions[model_key] = current_pos
		if not move_data.get("original_rotations", {}).has(model_key):
			if not move_data.has("original_rotations"):
				move_data["original_rotations"] = {}
			move_data["original_rotations"][model_key] = model.get("rotation", 0.0)

	# Calculate distance for this stage
	var distance_inches = Measurement.distance_inches(current_pos, dest_vec)

	# Check for enemy crossing (Fall Back)
	var crosses_enemy = false
	if move_data.mode == "FALL_BACK":
		crosses_enemy = _path_crosses_enemy(current_pos, dest_vec, unit_id, model.get("base_mm", 32))

	# T-082 fix: path-summed distance, not Euclidean origin→dest.
	# Re-staging through a waypoint must accumulate |A→B| + |B→C|, not collapse to |A→C|.
	var original_pos = move_data.original_positions.get(model_key, current_pos)
	var prior_total = move_data.model_distances.get(model_key, 0.0)
	# Per-segment terrain penalty (difficult ground only — flat per piece crossed).
	var terrain_penalty = _get_movement_terrain_penalty(current_pos, dest_vec, unit_id)
	var total_distance_for_model = prior_total + distance_inches + terrain_penalty

	# Remove any existing staged move for this model to prevent duplicates
	var moves_to_remove = []
	for i in range(move_data.staged_moves.size()):
		if move_data.staged_moves[i].model_id == model_id and move_data.staged_moves[i].get("model_source_unit_id", unit_id) == model_actual_unit_id:
			moves_to_remove.append(i)

	# Remove in reverse order to maintain indices
	for i in range(moves_to_remove.size() - 1, -1, -1):
		move_data.staged_moves.remove_at(moves_to_remove[i])

	# Add the new staged move
	move_data.staged_moves.append({
		"model_id": model_id,
		"model_source_unit_id": model_actual_unit_id,
		"from": current_pos,
		"dest": dest_vec,
		"rotation": rotation,  # Preserve rotation
		"distance": distance_inches,  # Keep individual segment distance for display
		"total_distance": total_distance_for_model,  # Track total from origin
		"crosses_enemy": crosses_enemy
	})

	# Update per-model distance tracking
	move_data.model_distances[model_key] = total_distance_for_model
	
	# Calculate effective cap accounting for pivot cost
	var effective_cap = move_data.move_cap_inches
	if move_data.get("pivot_cost_applied", false):
		effective_cap -= move_data.get("pivot_value", 0.0)

	DebugLogger.info(str("  - Distance this segment: ", distance_inches, "\""))
	DebugLogger.info(str("  - Total distance from origin: ", total_distance_for_model, "\""))
	DebugLogger.info(str("  - Remaining for this model: ", (effective_cap - total_distance_for_model), "\""))
	if move_data.get("pivot_cost_applied", false):
		DebugLogger.info(str("  - Pivot cost applied: ", move_data.get("pivot_value", 0.0), "\""))

	# Emit both signals for visual update
	# Use model_actual_unit_id so visual tokens (which are keyed by their real unit_id) are found
	emit_signal("model_drop_preview", model_actual_unit_id, model_id, [current_pos, dest_vec], distance_inches, true)
	# Also emit committed signal so model visually moves (but game state not updated)
	emit_signal("model_drop_committed", model_actual_unit_id, model_id, dest_vec, rotation)

	# Return result without state changes (staged only)
	return create_result(true, [], "", {
		"staged": true,
		"model_distance": total_distance_for_model,
		"model_remaining": effective_cap - total_distance_for_model,
		"model_distances": move_data.model_distances,
		"pivot_cost_applied": move_data.get("pivot_cost_applied", false),
		"pivot_value": move_data.get("pivot_value", 0.0)
	})

## T03 BEGIN_MODEL_DRAG (validated above): no game state changes — picking a
## model up moves nothing. The controller does the pick-up on the signal.
func _process_begin_model_drag(action: Dictionary) -> Dictionary:
	var unit_id: String = str(action.get("actor_unit_id", ""))
	var payload: Dictionary = action.get("payload", {})
	var model_id: String = str(payload.get("model_id", ""))
	var owner_unit_id := _begin_model_drag_owner(unit_id, model_id, str(payload.get("model_source_unit_id", "")))
	log_phase_message("BEGIN_MODEL_DRAG: %s picks up %s (%s)" % [unit_id, model_id, owner_unit_id])
	emit_signal("model_drag_requested", unit_id, model_id, owner_unit_id)
	return create_result(true, [], "", {"model_id": model_id, "model_source_unit_id": owner_unit_id})

func _process_undo_last_model_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var move_data = active_moves[unit_id]

	# Build lookup of attached character IDs for resolving model ownership
	var undo_unit = get_unit(unit_id)
	var undo_attached_chars = undo_unit.get("attachment_data", {}).get("attached_characters", [])

	# Helper to resolve which unit owns a model (checks source hint first to avoid
	# model ID collisions when bodyguard and character share IDs like "m1")
	var _resolve_undo_owner = func(mid: String, source_hint: String = "") -> Dictionary:
		if source_hint != "" and source_hint != unit_id:
			var idx = _get_model_index(source_hint, mid)
			if idx >= 0:
				return {"unit_id": source_hint, "index": idx}
		var idx = _get_model_index(unit_id, mid)
		if idx >= 0:
			return {"unit_id": unit_id, "index": idx}
		for cid in undo_attached_chars:
			idx = _get_model_index(cid, mid)
			if idx >= 0:
				return {"unit_id": cid, "index": idx}
		return {"unit_id": unit_id, "index": -1}

	# Prefer undoing staged moves (current system), fall back to model_moves (legacy)
	if not move_data.staged_moves.is_empty():
		var last_staged = move_data.staged_moves.pop_back()
		var model_id = last_staged.model_id
		var undo_source = last_staged.get("model_source_unit_id", "")
		var undo_source_resolved = undo_source if undo_source != "" else unit_id
		var model_key = "%s:%s" % [undo_source_resolved, model_id]
		var original_pos = move_data.original_positions.get(model_key)

		DebugLogger.info(str("[MovementPhase] Undoing staged move for model %s (key %s), restoring to %s" % [model_id, model_key, str(original_pos)]))

		# Check if this model has any remaining staged moves
		var has_remaining_staged = false
		for staged_move in move_data.staged_moves:
			if staged_move.model_id == model_id and staged_move.get("model_source_unit_id", unit_id) == undo_source_resolved:
				has_remaining_staged = true
				break

		# If no more staged moves for this model, clear its tracking data and restore rotation
		var changes = []
		if not has_remaining_staged:
			move_data.model_distances.erase(model_key)
			move_data.original_positions.erase(model_key)

			# Restore original rotation for this model
			var original_rotations = move_data.get("original_rotations", {})
			if original_rotations.has(model_key):
				var original_rot = original_rotations[model_key]
				var owner_info = _resolve_undo_owner.call(model_id, undo_source)
				if owner_info.index >= 0:
					changes.append({
						"op": "set",
						"path": "units.%s.models.%s.rotation" % [owner_info.unit_id, owner_info.index],
						"value": original_rot
					})
					DebugLogger.info(str("[MovementPhase] Restoring rotation for model %s to %.2f" % [model_id, original_rot]))
				original_rotations.erase(model_key)

		# If no more staged moves at all, reset pivot cost
		if move_data.staged_moves.is_empty():
			move_data["pivot_cost_applied"] = false
			DebugLogger.info("[MovementPhase] All staged moves undone, resetting pivot cost")

		# Restore to original position (before any movement this phase)
		if original_pos:
			# Resolve the actual unit that owns this model for visual update
			var owner_info = _resolve_undo_owner.call(model_id, undo_source)
			var actual_unit_id = owner_info.unit_id if owner_info.index >= 0 else unit_id
			var model = _get_model_in_unit(actual_unit_id, model_id)
			var original_rotation = model.get("rotation", 0.0)
			emit_signal("model_drop_committed", actual_unit_id, model_id, original_pos, original_rotation)
			return create_result(true, [])
		else:
			return create_result(true, changes)

	# If no staged moves, check if there are rotation-only changes to undo
	if move_data.model_moves.is_empty():
		var rotation_changes = []
		var original_rotations = move_data.get("original_rotations", {})
		if not original_rotations.is_empty():
			for rot_composite_key in original_rotations.keys():
				var original_rot = original_rotations[rot_composite_key]
				var rot_parts = rot_composite_key.split(":")
				var rot_source_uid = rot_parts[0] if rot_parts.size() > 1 else unit_id
				var rot_mid = rot_parts[rot_parts.size() - 1]
				var model_idx = _get_model_index(rot_source_uid, rot_mid)
				if model_idx >= 0:
					rotation_changes.append({
						"op": "set",
						"path": "units.%s.models.%s.rotation" % [rot_source_uid, model_idx],
						"value": original_rot
					})
					DebugLogger.info(str("[MovementPhase] Restoring rotation-only change for model %s to %.2f" % [rot_mid, original_rot]))
			original_rotations.clear()
			move_data["pivot_cost_applied"] = false
			return create_result(true, rotation_changes)
		return create_result(false, [], "No moves to undo")

	var last_move = move_data.model_moves.pop_back()
	var model_id = last_move.model_id
	var from_pos = last_move.from

	return create_result(true, [
		{
			"op": "set",
			"path": "units.%s.models.%s.position" % [unit_id, _get_model_index(unit_id, model_id)],
			"value": {"x": from_pos.x, "y": from_pos.y} if from_pos else null
		}
	])

func _process_reset_unit_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var move_data = active_moves[unit_id]
	var changes = []

	# Build lookup of attached character IDs for resolving model ownership
	var reset_unit = get_unit(unit_id)
	var reset_attached_chars = reset_unit.get("attachment_data", {}).get("attached_characters", [])

	# Reset models from staged moves to their original positions
	# original_positions uses composite keys "source_unit_id:model_id"
	for composite_key in move_data.original_positions:
		var original_pos = move_data.original_positions[composite_key]
		if original_pos:
			var parts = composite_key.split(":")
			var source_uid = parts[0] if parts.size() > 1 else unit_id
			var mid = parts[parts.size() - 1]
			var idx = _get_model_index(source_uid, mid)
			if idx >= 0:
				changes.append({
					"op": "set",
					"path": "units.%s.models.%s.position" % [source_uid, idx],
					"value": {"x": original_pos.x, "y": original_pos.y}
				})

	# Reset model rotations to their original values
	var original_rotations = move_data.get("original_rotations", {})
	for composite_key in original_rotations:
		var original_rot = original_rotations[composite_key]
		var parts = composite_key.split(":")
		var source_uid = parts[0] if parts.size() > 1 else unit_id
		var mid = parts[parts.size() - 1]
		var idx = _get_model_index(source_uid, mid)
		if idx >= 0:
			changes.append({
				"op": "set",
				"path": "units.%s.models.%s.rotation" % [source_uid, idx],
				"value": original_rot
			})
			DebugLogger.info(str("[MovementPhase] Resetting rotation for model %s to %.2f" % [mid, original_rot]))

	# Reset all model positions from permanent moves (if any)
	for model_move in move_data.model_moves:
		var from_pos = model_move.from
		var source = model_move.get("model_source_unit_id", unit_id)
		var mid = model_move.model_id
		var owner_uid = source if source != "" else unit_id
		var idx = _get_model_index(owner_uid, mid)
		if idx < 0:
			idx = _get_model_index(unit_id, mid)
			owner_uid = unit_id
		if idx < 0:
			for cid in reset_attached_chars:
				idx = _get_model_index(cid, mid)
				if idx >= 0:
					owner_uid = cid
					break
		if idx >= 0:
			changes.append({
				"op": "set",
				"path": "units.%s.models.%s.position" % [owner_uid, idx],
				"value": {"x": from_pos.x, "y": from_pos.y} if from_pos else null
			})

	# Clear all move data
	move_data.model_moves.clear()
	move_data.staged_moves.clear()
	move_data.model_distances.clear()  # Clear per-model distances
	move_data.original_positions.clear()
	if move_data.has("original_rotations"):
		move_data["original_rotations"].clear()
	move_data["pivot_cost_applied"] = false  # Reset pivot cost on move reset

	# Clear movement_active flag (synced across network)
	changes.append({
		"op": "remove",
		"path": "units.%s.flags.movement_active" % unit_id
	})
	# Also clear move_cap_inches since the move is being reset
	changes.append({
		"op": "remove",
		"path": "units.%s.flags.move_cap_inches" % unit_id
	})
	# Clear fell_back flag if it was set during BEGIN_FALL_BACK
	if move_data.mode == "FALL_BACK":
		changes.append({
			"op": "remove",
			"path": "units.%s.flags.fell_back" % unit_id
		})
	# Clear advanced flag if it was set during BEGIN_ADVANCE
	if move_data.mode == "ADVANCE":
		changes.append({
			"op": "remove",
			"path": "units.%s.flags.advanced" % unit_id
		})

	# Remove from local tracking
	active_moves.erase(unit_id)

	emit_signal("unit_move_reset", unit_id)

	# Codex: Orks (11e): resetting a reactive follow-up move keeps that move
	# available (same maximum distance) — the stratagem has been paid for.
	if str(_ork11e_reactive_move.get("unit_id", "")) == unit_id:
		_ork11e_setup_reactive_active_move(unit_id, float(_ork11e_reactive_move.get("max_inches", 0.0)), str(_ork11e_reactive_move.get("source", "")))
		emit_signal("unit_move_begun", unit_id, "NORMAL")

	return create_result(true, changes)

func _process_confirm_unit_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var move_data = active_moves[unit_id]
	var changes = []
	var additional_dice = []

	DebugLogger.info(str("[MovementPhase] Confirming unit move with ", move_data.staged_moves.size(), " staged moves"))

	# Get unique model IDs
	var unique_models = {}
	for staged_move in move_data.staged_moves:
		unique_models[staged_move.model_id] = true
	DebugLogger.info(str("[MovementPhase] Processing ", unique_models.size(), " unique models"))

	# Build lookup of attached character IDs for resolving model ownership
	var _confirm_unit = get_unit(unit_id)
	var _confirm_attached_chars = _confirm_unit.get("attachment_data", {}).get("attached_characters", [])

	# Convert staged moves to permanent moves
	for staged_move in move_data.staged_moves:
		DebugLogger.info(str("  Confirming move for model ", staged_move.model_id, " to ", staged_move.dest))
		# Add to permanent moves (include source unit for model ID collision resolution)
		move_data.model_moves.append({
			"model_id": staged_move.model_id,
			"model_source_unit_id": staged_move.get("model_source_unit_id", unit_id),
			"from": staged_move.get("from"),
			"dest": staged_move.dest,
			"rotation": staged_move.get("rotation", 0.0),
			"crosses_enemy": staged_move.get("crosses_enemy", false)
		})

		# Resolve which unit actually owns this model (bodyguard or attached character)
		# Use model_source_unit_id from staging to avoid model ID collisions (e.g. both
		# bodyguard and character having "m1")
		var staged_source = staged_move.get("model_source_unit_id", "")
		var model_owner_id = unit_id
		var model_idx = -1

		if staged_source != "" and staged_source != unit_id:
			model_idx = _get_model_index(staged_source, staged_move.model_id)
			if model_idx >= 0:
				model_owner_id = staged_source
				DebugLogger.info(str("  Model %s belongs to source unit %s (index %d)" % [staged_move.model_id, staged_source, model_idx]))

		if model_idx < 0:
			model_idx = _get_model_index(unit_id, staged_move.model_id)
		if model_idx < 0:
			for char_id in _confirm_attached_chars:
				model_idx = _get_model_index(char_id, staged_move.model_id)
				if model_idx >= 0:
					model_owner_id = char_id
					DebugLogger.info(str("  Model %s belongs to attached character %s (index %d)" % [staged_move.model_id, char_id, model_idx]))
					break

		# Update model position in game state
		changes.append({
			"op": "set",
			"path": "units.%s.models.%s.position" % [model_owner_id, model_idx],
			"value": {"x": staged_move.dest.x, "y": staged_move.dest.y}
		})

		# Update model rotation in game state
		changes.append({
			"op": "set",
			"path": "units.%s.models.%s.rotation" % [model_owner_id, model_idx],
			"value": staged_move.get("rotation", 0.0)
		})
	
	# 11e [HEAVY] (24.16): record the max distance any model moved this turn so
	# the hit-modifier stack can grant +1 to hit when the unit moved <=3".
	var _max_moved := 0.0
	for _d in move_data.model_distances.values():
		_max_moved = max(_max_moved, float(_d))
	changes.append({
		"op": "set",
		"path": "units.%s.flags.moved_max_inches" % unit_id,
		"value": _max_moved
	})

	# Clear staged moves after converting them
	move_data.staged_moves.clear()
	move_data.accumulated_distance = 0.0

	# Build lookup of explicitly moved models using unit_id:model_id keys to avoid
	# collision when bodyguard and character units share model IDs like "m1"
	var explicitly_moved_model_keys = {}
	for mm in move_data.model_moves:
		var source = mm.get("model_source_unit_id", unit_id)
		explicitly_moved_model_keys["%s:%s" % [source, mm.model_id]] = true

	var bg_models = _confirm_unit.get("models", [])
	var bg_model_ids = {}
	for bg_m in bg_models:
		if bg_m.get("alive", true):
			bg_model_ids[bg_m.get("id", "")] = true

	# Check if any bodyguard model was explicitly moved (using source unit to disambiguate)
	var any_bg_model_moved = false
	for mm in move_data.model_moves:
		var source = mm.get("model_source_unit_id", unit_id)
		if source == unit_id and mm.model_id in bg_model_ids:
			any_bg_model_moved = true
			break

	# If only character models were moved, auto-move bodyguard models by the same delta
	if not any_bg_model_moved and move_data.model_moves.size() > 0:
		var first_move = move_data.model_moves[0]
		var from_pos = first_move.get("from", null)
		var to_pos = first_move.get("dest", null)
		if from_pos != null and to_pos != null:
			var from_vec = Vector2(from_pos.x if from_pos is Vector2 else from_pos.get("x", 0), from_pos.y if from_pos is Vector2 else from_pos.get("y", 0))
			var to_vec = Vector2(to_pos.x if to_pos is Vector2 else to_pos.get("x", 0), to_pos.y if to_pos is Vector2 else to_pos.get("y", 0))
			var move_delta = to_vec - from_vec
			DebugLogger.info(str("[MovementPhase] No bodyguard models explicitly moved — auto-moving bodyguard with character delta: %s" % str(move_delta)))
			for bg_m in bg_models:
				if not bg_m.get("alive", true):
					continue
				var bg_mid = bg_m.get("id", "")
				var bg_key = "%s:%s" % [unit_id, bg_mid]
				if explicitly_moved_model_keys.has(bg_key):
					continue
				var model_pos = bg_m.get("position", null)
				if model_pos == null:
					continue
				var pos_x = model_pos.get("x", 0) if model_pos is Dictionary else model_pos.x
				var pos_y = model_pos.get("y", 0) if model_pos is Dictionary else model_pos.y
				var new_pos = Vector2(pos_x + move_delta.x, pos_y + move_delta.y)
				var bg_idx = _get_model_index(unit_id, bg_mid)
				if bg_idx >= 0:
					changes.append({
						"op": "set",
						"path": "units.%s.models.%d.position" % [unit_id, bg_idx],
						"value": {"x": new_pos.x, "y": new_pos.y}
					})
					DebugLogger.info(str("[MovementPhase] Auto-moved bodyguard model %s by delta %s" % [bg_mid, str(move_delta)]))

	# Move attached character models with the bodyguard unit
	# Skip character models that were already explicitly moved via staged moves
	var attached_chars = _confirm_unit.get("attachment_data", {}).get("attached_characters", [])
	if attached_chars.size() > 0:
		changes.append_array(_move_attached_characters(unit_id, attached_chars, explicitly_moved_model_keys, changes))

	# Ensure all attached characters are marked as moved even if _move_attached_characters
	# returned early (e.g. no bodyguard delta found because only character models were staged)
	for char_id in attached_chars:
		changes.append({
			"op": "set",
			"path": "units.%s.flags.moved" % char_id,
			"value": true
		})

	# Handle Desperate Escape for Fall Back.
	# ISS-064 (11e 09.07): at edition >= 11 the desperate-escape BEFORE-MOVING
	# hazard rolls (06.03) are already applied at BEGIN_FALL_BACK by the
	# FallBackMove template; running the legacy 10e per-model destruction here
	# too would double-apply (two different mechanics). Gate it to 10e only.
	if move_data.mode == "FALL_BACK" and GameConstants.edition < 11:
		var desperate_escape_result = _process_desperate_escape(unit_id, move_data)
		changes.append_array(desperate_escape_result.changes)
		additional_dice.append_array(desperate_escape_result.dice)

	# Mark unit as moved
	changes.append({
		"op": "set",
		"path": "units.%s.flags.moved" % unit_id,
		"value": true
	})
	
	# Clear temporary move data
	changes.append({
		"op": "remove",
		"path": "units.%s.flags.move_cap_inches" % unit_id
	})

	# Clear movement_active flag (synced across network)
	changes.append({
		"op": "remove",
		"path": "units.%s.flags.movement_active" % unit_id
	})
	
	# P2-72: Track Normal moves for per-phase limit enforcement
	if move_data.mode == "NORMAL":
		_normal_moves_this_phase[unit_id] = true
		log_phase_message("P2-72: Marked %s as having made a Normal move this phase" % unit_id)

	# ISS-040 step 2: at 11e the confirmed move's template contributes its
	# AFTER effects (16.01 action locks, desperate-escape battle-shock
	# follow-up). Duplicate set-ops with the legacy flags below are
	# idempotent.
	if GameConstants.edition >= 11:
		var mt_map_11e = {"NORMAL": "normal", "ADVANCE": "advance", "FALL_BACK": "fall_back"}
		if mt_map_11e.has(move_data.mode):
			var mt_fx = MoveTypes.get_type(mt_map_11e[move_data.mode]).after_moving_effects(
				unit_id, {"mode": str(move_data.get("fall_back_mode", ""))})
			# Codex: Orks (11e) MIND MOSTLY ON THE MISSION: "That move does not
			# prevent your unit from being eligible to start an action" — drop the
			# advance / fall-back 16.01 action lock (ActionsManager also ignores
			# the advanced / fell_back flags for this unit).
			# (WP-O34: also Runt Swarm's Sneaky Little Gitz for a GRETCHIN unit.)
			# Codex: Adeptus Custodes (11e) Emissaries Imperatus — Favoured Conservai
			# rider: the same "does not prevent ... eligible to start an action" (WP-C46).
			var cus11e_conservai: bool = _cus11e_det().move_keeps_action_eligibility(get_unit(unit_id))
			# WP-M4b FLEXIBLE ASSET (Codex: Space Marines 11e, Scout Squad): the same rider.
			var sm11e_flexible: bool = load("res://scripts/codex/space_marines/SMAbilitiesB.gd").move_keeps_action_eligibility(get_unit(unit_id))
			cus11e_conservai = cus11e_conservai or sm11e_flexible
			if move_data.mode in ["ADVANCE", "FALL_BACK"] \
					and (get_unit(unit_id).get("flags", {}).get(Ork11eMovement.FLAG_MIND_ON_MISSION, false)
						or Ork11eDetachments.move_keeps_action_eligibility(get_unit(unit_id))
						or cus11e_conservai):
				mt_fx = mt_fx.filter(func(fx): return not str(fx.get("path", "")).ends_with(".cannot_start_action"))
				var keep_src: String = "MIND MOSTLY ON THE MISSION"
				if Ork11eDetachments.move_keeps_action_eligibility(get_unit(unit_id)):
					keep_src = "Sneaky Little Gitz (Runt Swarm)"
				elif sm11e_flexible:
					keep_src = "Flexible Asset (Scout Squad)"
				elif cus11e_conservai:
					keep_src = "Conservai (Heralds of the Throne)"
				log_phase_message("[11e] %s — %s's %s move leaves it eligible to start an action" % [
					keep_src, unit_id, move_data.mode])
			changes.append_array(mt_fx)
			log_phase_message("[11e] Applied %s template AFTER effects for %s (%d ops)" % [mt_map_11e[move_data.mode], unit_id, mt_fx.size()])
			# 09.07 AFTER MOVING (desperate escape): "If your unit is not
			# battle-shocked, you must make a battle-shock roll" — resolve the
			# template's pending_battleshock_roll with the engine's out-of-
			# Command-phase roll (a failure makes the unit battle-shocked, which
			# opens its unit_battle_shocked stratagem window).
			if move_data.mode == "FALL_BACK" and str(move_data.get("fall_back_mode", "")) == "desperate_escape":
				var de_shocked: bool = GameState.get_unit(unit_id).get("flags", {}).get("battle_shocked", false)
				if not de_shocked and has_node("/root/FactionAbilityManager"):
					var de_roll: Dictionary = get_node("/root/FactionAbilityManager").force_battle_shock_test(unit_id, 0, "Desperate Escape")
					changes.append_array(de_roll.get("diffs", []))
					log_phase_message("[11e 09.07] Desperate escape battle-shock roll for %s: %s = %d vs Ld %d — %s" % [
						unit_id, str(de_roll.get("dice", [])), int(de_roll.get("total", 0)), int(de_roll.get("leadership", 0)),
						"passed" if de_roll.get("passed", true) else "battle-shocked"])
				changes.append({"op": "set", "path": "units.%s.flags.pending_battleshock_roll" % unit_id, "value": false})

	# ISS-073 (11e 24.35): a SUPER-HEAVY WALKER that opted its models into MOBILE
	# for this move (to cross dense/difficult terrain) gambles at move end: roll
	# one D6 — on a 1 the unit becomes battle-shocked. Deterministic via the
	# action payload rng_seed (network seed when hosting).
	if move_data.get("shw_mobile", false):
		var shw_seed = action.get("payload", {}).get("rng_seed", -1)
		if shw_seed == -1 and has_node("/root/NetworkManager"):
			var nm = get_node("/root/NetworkManager")
			if nm.is_networked() and nm.is_host():
				shw_seed = nm.get_next_rng_seed()
		var shw_rng = RulesEngine.RNGService.new(shw_seed)
		var shw_roll = shw_rng.roll_d6(1)[0]
		additional_dice.append({
			"context": "shw_mobile_gamble",
			"n": 1,
			"rolls": [shw_roll]
		})
		var shw_name = get_unit(unit_id).get("meta", {}).get("name", unit_id)
		if shw_roll == 1:
			changes.append({
				"op": "set",
				"path": "units.%s.flags.battle_shocked" % unit_id,
				"value": true
			})
			dice_log.append({
				"unit_id": unit_id,
				"unit_name": shw_name,
				"type": "Super-Heavy Walker MOBILE gamble",
				"rolls": [shw_roll],
				"result": "battle-shocked"
			})
			log_phase_message("[11e 24.35] %s gambled MOBILE — rolled 1 → battle-shocked" % shw_name)
		else:
			log_phase_message("[11e 24.35] %s gambled MOBILE — rolled %d → safe" % [shw_name, shw_roll])

	# Set movement restrictions for later phases
	if move_data.mode == "ADVANCE":
		# ASSAULT RULES: Set the 'advanced' flag for Shooting phase to check
		# Units that Advanced can shoot with Assault weapons only
		changes.append({
			"op": "set",
			"path": "units.%s.flags.advanced" % unit_id,
			"value": true
		})
		changes.append({
			"op": "set",
			"path": "units.%s.flags.cannot_charge" % unit_id,
			"value": true
		})
		# Propagate advance flags to attached characters
		for char_id in attached_chars:
			changes.append({
				"op": "set",
				"path": "units.%s.flags.advanced" % char_id,
				"value": true
			})
			changes.append({
				"op": "set",
				"path": "units.%s.flags.cannot_charge" % char_id,
				"value": true
			})
			DebugLogger.info(str("[MovementPhase] Propagated advance flags to attached character %s" % char_id))
		# Turbo Boostas (Speedwaaagh!): the turbo grants ranged weapons ASSAULT
		# (advance-and-shoot) until end of turn, and hard-locks charging — the
		# turbo_boosted flag cannot be overridden by advance-and-charge effects.
		if move_data.get("turbo_boost", false):
			for tb_id in [unit_id] + attached_chars:
				changes.append({
					"op": "set",
					"path": "units.%s.flags.turbo_boosted" % tb_id,
					"value": true
				})
				changes.append({
					"op": "set",
					"path": "units.%s.flags.effect_advance_and_shoot" % tb_id,
					"value": true
				})
			DebugLogger.info(str("[MovementPhase] Turbo Boostas — %s gains ASSAULT ranged weapons and cannot charge this turn" % unit_id))
	elif move_data.mode == "FALL_BACK":
		# Set fell_back flag - units that Fell Back cannot shoot or charge
		changes.append({
			"op": "set",
			"path": "units.%s.flags.fell_back" % unit_id,
			"value": true
		})
		changes.append({
			"op": "set",
			"path": "units.%s.flags.cannot_shoot" % unit_id,
			"value": true
		})
		changes.append({
			"op": "set",
			"path": "units.%s.flags.cannot_charge" % unit_id,
			"value": true
		})
		# Propagate fall back flags to attached characters
		for char_id in attached_chars:
			changes.append({
				"op": "set",
				"path": "units.%s.flags.fell_back" % char_id,
				"value": true
			})
			changes.append({
				"op": "set",
				"path": "units.%s.flags.cannot_shoot" % char_id,
				"value": true
			})
			changes.append({
				"op": "set",
				"path": "units.%s.flags.cannot_charge" % char_id,
				"value": true
			})
			DebugLogger.info(str("[MovementPhase] Propagated fall back flags to attached character %s" % char_id))
	elif move_data.mode == "SURGE":
		# Set surge_moved flag — surge moves don't restrict shooting/charging
		# but track that a surge happened (P2-71)
		changes.append({
			"op": "set",
			"path": "units.%s.flags.surge_moved" % unit_id,
			"value": true
		})
		# Propagate surge flag to attached characters
		for char_id in attached_chars:
			changes.append({
				"op": "set",
				"path": "units.%s.flags.surge_moved" % char_id,
				"value": true
			})
		emit_signal("surge_move_completed", unit_id, move_data.move_cap_inches)

	# OA-8: If this was a Krump and Run reactive move, clear the reactive state
	if move_data.get("is_reactive_move", false) and move_data.get("reactive_source", "") == "krump_and_run":
		_reactive_move_owner = 0
		_krump_and_run_unit_id = ""
		# Krump and Run normal move — unit can still shoot and charge normally
		# (it's a Normal move, not a Fall Back)
		changes.append({
			"op": "set",
			"path": "units.%s.flags.moved" % unit_id,
			"value": true
		})
		log_phase_message("OA-8: Krump and Run reactive move completed for %s" % unit_id)
		DebugLogger.info(str("MovementPhase: OA-8 Krump and Run move completed for %s — reactive state cleared" % unit_id))
		move_data["completed"] = true
		emit_signal("unit_move_confirmed", unit_id, {"mode": "NORMAL", "models_moved": move_data.model_moves.size()})
		if MissionManager:
			MissionManager.call_deferred("check_all_objectives", false)
		return _ork11e_with_enemy_ended_move(create_result(true, changes))

	# OA-42: If this was a Scatter! reactive move, clear the reactive state
	if move_data.get("is_reactive_move", false) and move_data.get("reactive_source", "") == "scatter":
		_reactive_move_owner = 0
		_scatter_unit_id = ""
		# Scatter! normal move — unit can still shoot and charge normally
		changes.append({
			"op": "set",
			"path": "units.%s.flags.moved" % unit_id,
			"value": true
		})
		log_phase_message("OA-42: Scatter! reactive move completed for %s" % unit_id)
		DebugLogger.info(str("MovementPhase: OA-42 Scatter! move completed for %s — reactive state cleared" % unit_id))
		move_data["completed"] = true
		emit_signal("unit_move_confirmed", unit_id, {"mode": "NORMAL", "models_moved": move_data.model_moves.size()})
		if MissionManager:
			MissionManager.call_deferred("check_all_objectives", false)
		return _ork11e_with_enemy_ended_move(create_result(true, changes))

	# Codex: Orks (11e) reactive normal move (SCARPER! / WHIRLIGIG EVASION /
	# WHILE THEIR BACKS ARE TURNED follow-up, design §3.2): clear the reactive
	# state and continue the stratagem-window flow the follow-up paused.
	if move_data.get("is_reactive_move", false) and move_data.get("reactive_source", "") == "ork11e":
		_reactive_move_owner = 0
		var rm_source := str(move_data.get("ork11e_source", "reactive move"))
		var rm_player := int(_ork11e_reactive_move.get("player", get_unit(unit_id).get("owner", 0)))
		_ork11e_reactive_move = {}
		move_data["completed"] = true
		var rm_max := 0.0
		for d in move_data.model_distances.values():
			rm_max = max(rm_max, float(d))
		log_phase_message("%s: reactive normal move completed for %s (%.1f\" of %.1f\")" % [rm_source, unit_id, rm_max, float(move_data.move_cap_inches)])
		var rm_log = get_node_or_null("/root/GameEventLog")
		if rm_log and not _ork11e_auto_moving:
			rm_log.add_player_entry(rm_player, "%s: %s made a normal move of %.1f\"" % [rm_source, get_unit(unit_id).get("meta", {}).get("name", unit_id), rm_max])
		emit_signal("unit_move_confirmed", unit_id, {"mode": "NORMAL", "models_moved": move_data.model_moves.size()})
		if MissionManager:
			MissionManager.call_deferred("check_all_objectives", false)
		if _ork11e_auto_moving:
			return create_result(true, changes)
		return _finish_window_followup(changes)

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Confirmed %s move for %s" % [move_data.mode.to_lower(), unit_name])
	
	# Mark unit as completed before cleanup
	move_data["completed"] = true

	emit_signal("unit_move_confirmed", unit_id, {"mode": move_data.mode, "models_moved": move_data.model_moves.size()})

	# T7-39: Recheck objective control after movement so flashes trigger in real-time
	# Uses call_deferred so it runs after GameManager.apply_result() applies the position diffs
	if MissionManager:
		MissionManager.call_deferred("check_all_objectives", false)

	# Check for embark opportunity after movement
	if not unit.get("disembarked_this_phase", false):
		call_deferred("_check_embark_opportunity", unit_id)

	# Codex: Orks (11e): remember the move that just ended - the opponent's
	# enemy_ended_move window opens once the overwatch / Krump and Run /
	# Scatter! prompts below have resolved (_ork11e_try_enemy_ended_move_window).
	_ork11e_eem_pending = {"unit_id": unit_id, "move_type": _ork11e_move_type(str(move_data.mode))}

	# WP-O6 SHOKK-BOOSTA (Codex: Orks 11e, Big Mek): "When this unit ends that
	# advance move, make a hazard roll for each model in this unit."
	if move_data.mode == "ADVANCE" and GameConstants.edition >= 11 and OrkAbilities11eScript.shokk_boosta_active(unit_id):
		var sb_diffs: Array = OrkAbilities11eScript.on_advance_move_ended(unit_id)
		changes.append_array(sb_diffs)
		log_phase_message("Shokk-boosta: %s ended its boosted advance — hazard rolls made (%d diff(s))" % [unit_name, sb_diffs.size()])

	# Codex: Orks (11e) unit_ended_normal_move window (active player). 01.03.02:
	# the active player's rules resolve before the opponent's (overwatch, ...).
	# Codex: Adeptus Custodes (CustodesCodex11e.gd): the same hook opens unit_ended_advance_move after an advance move.
	if (move_data.mode == "NORMAL" or move_data.mode == "ADVANCE") and GameConstants.edition >= 11:
		var uenm_window := "unit_ended_normal_move" if move_data.mode == "NORMAL" else "unit_ended_advance_move"
		var uenm_ctx := {"phase": "movement", "unit_id": unit_id}
		uenm_ctx["sm11e_from_positions"] = _sm11e_from_positions(unit_id, move_data)  # WP-M4a THUNDERHAWK CLUSTER BOMBS: "moved over"
		var uenm_staged := _ork11e_stage_move_positions(changes)
		var uenm_opened := open_stratagem_window(get_current_player(), uenm_window, uenm_ctx, "_resume_after_unit_ended_normal_move")
		_ork11e_restore_move_positions(uenm_staged)
		if uenm_opened:
			log_phase_message("Waiting for Player %d's %s stratagem decision for %s" % [get_current_player(), uenm_window, unit_id])
			var uenm_paused: Array = changes.duplicate()
			uenm_paused.append_array(consume_window_diffs())
			return create_result(true, uenm_paused, "", {"dice": additional_dice})
		changes.append_array(consume_window_diffs())

	return _post_move_prompts(unit_id, move_data, changes, additional_dice)

## Prompts after a confirmed move: Fire Overwatch, Krump and Run, Scatter!, then
## the Codex: Orks (11e) enemy_ended_move window, then the moving unit's own
## post-move abilities (_post_move_active_abilities). Split out of
## _process_confirm_unit_move so the unit_ended_normal_move window can resume it.
func _post_move_prompts(unit_id: String, move_data: Dictionary, changes: Array, additional_dice: Array) -> Dictionary:
	# Codex: Orks (11e): the prompts below can be answered INSIDE this action
	# (e.g. "Skip Overwatch" auto-declines synchronously, and that nested
	# DECLINE opens enemy_ended_move) before BasePhase has applied `changes`.
	# Keep them so that window sees the moved models where they ended.
	_ork11e_pending_move_changes = changes.duplicate()
	# T3-11 / P2-88: Check for Fire Overwatch opportunity for the defending player
	# Balance Dataslate timing: "when an enemy unit ends a Normal, Advance or Fall Back move"
	# Build a temporary snapshot with the new positions applied for range checks
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

	var ow_result = _check_fire_overwatch_opportunity(unit_id, "move end", temp_snapshot)
	if ow_result.triggered:
		# OA-8: If this was a Fall Back, defer Krump and Run check until overwatch resolves
		if move_data.mode == "FALL_BACK":
			_krump_and_run_pending_after_overwatch = true
			_krump_and_run_pending_fell_back_id = unit_id
			DebugLogger.info("MovementPhase: OA-8 Krump and Run check deferred — Fire Overwatch triggered first")
		# OA-42: Defer Scatter! check until overwatch resolves
		_scatter_pending_after_overwatch = true
		_scatter_pending_trigger_id = unit_id
		_scatter_pending_changes = changes.duplicate()
		_scatter_pending_dice = additional_dice.duplicate() if additional_dice is Array else []
		DebugLogger.info("MovementPhase: OA-42 Scatter! check deferred — Fire Overwatch triggered first")
		var result = create_result(true, changes, "", {"dice": additional_dice})
		result.merge(ow_result.result_extra)
		return result

	# OA-8: Check for Krump and Run opportunity after Fall Back (no overwatch triggered)
	if move_data.mode == "FALL_BACK":
		var kar_result = _check_krump_and_run_opportunity(unit_id, temp_snapshot)
		if kar_result.triggered:
			var result = create_result(true, changes, "", {"dice": additional_dice})
			result.merge(kar_result.result_extra)
			return result

	# OA-42: Check for Scatter! opportunity after Normal, Advance or Fall Back move
	var scatter_result = _check_scatter_opportunity(unit_id, temp_snapshot)
	if scatter_result.triggered:
		var result = create_result(true, changes, "", {"dice": additional_dice})
		result.merge(scatter_result.result_extra)
		return result

	# Codex: Orks (11e) enemy_ended_move window (the opponent), after the
	# overwatch / Krump and Run / Scatter! prompts above.
	var eem := _ork11e_try_enemy_ended_move_window(true)
	if eem.paused:
		var eem_paused: Array = changes.duplicate()
		eem_paused.append_array(eem.diffs)
		return create_result(true, eem_paused, "", {"dice": additional_dice})
	changes.append_array(eem.diffs)
	return _post_move_active_abilities(unit_id, move_data, changes, additional_dice)

## The moving unit's own post-move abilities — resumed after the
## enemy_ended_move window. (Codex: Orks (11e) Bomb Squigs is a
## unit_ended_normal_move window ability — OrkAbilities11e.gd; the 10e
## Quicksilver Execution fly-over is gone — the codex rule is melee
## [SUSTAINED HITS 1], CustodesAbilities.gd.)
func _post_move_active_abilities(_unit_id: String, _move_data: Dictionary, changes: Array, additional_dice: Array) -> Dictionary:
	return create_result(true, changes, "", {"dice": additional_dice})

func _process_remain_stationary(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)
	var is_disembarked = unit.get("disembarked_this_phase", false)
	var changes = _remain_stationary_changes(unit_id, unit)

	if is_disembarked:
		log_phase_message("%s remained stationary (disembarked this phase — no Heavy bonus)" % unit.get("meta", {}).get("name", unit_id))
	else:
		log_phase_message("%s remained stationary" % unit.get("meta", {}).get("name", unit_id))
	
	# Mark unit as completed in active_moves
	if active_moves.has(unit_id):
		active_moves[unit_id]["completed"] = true
	else:
		active_moves[unit_id] = {
			"mode": "REMAIN_STATIONARY",
			"mode_locked": true,
			"completed": true,
			"move_cap_inches": 0,
			"advance_roll": 0,
			"model_moves": [],
			"staged_moves": [],
			"original_positions": {},
			"original_rotations": {},
			"model_distances": {},
			"dice_rolls": [],
			# Multi-selection group movement support
			"group_moves": [],  # Track group movement operations
			"group_selection": [],  # Current multi-selected models
			"group_formation": {}  # Relative positions within group
		}
	
	emit_signal("unit_move_confirmed", unit_id, {"mode": "REMAIN_STATIONARY", "distance": 0})
	
	return create_result(true, changes)

## The state diffs of a Remain Stationary move (09.04) for unit_id (and its
## attached characters). Shared by the REMAIN_STATIONARY action and by
## END_MOVEMENT, which resolves every still-unselected unit as Remain
## Stationary (09.02 — see get_units_requiring_selection).
func _remain_stationary_changes(unit_id: String, unit: Dictionary) -> Array:
	# T3-15: Disembarked units do not count as Remained Stationary per 10e rules.
	# They don't get Heavy weapon bonus even if they choose not to move after disembarking.
	var is_disembarked = unit.get("disembarked_this_phase", false)

	var changes = [
		{
			"op": "set",
			"path": "units.%s.flags.moved" % unit_id,
			"value": true
		},
		{
			"op": "set",
			"path": "units.%s.flags.remained_stationary" % unit_id,
			"value": not is_disembarked
		},
		{
			# 11e [HEAVY]: stationary = moved 0"; disembarked units don't qualify.
			"op": "set",
			"path": "units.%s.flags.moved_max_inches" % unit_id,
			"value": 0.0 if not is_disembarked else 999.0
		}
	]

	# Propagate remain stationary flags to attached characters
	var attached_chars = unit.get("attachment_data", {}).get("attached_characters", [])
	for char_id in attached_chars:
		changes.append({
			"op": "set",
			"path": "units.%s.flags.moved" % char_id,
			"value": true
		})
		changes.append({
			"op": "set",
			"path": "units.%s.flags.remained_stationary" % char_id,
			"value": not is_disembarked
		})
		DebugLogger.info(str("[MovementPhase] Propagated remain stationary flags to attached character %s" % char_id))
	return changes

## T09 (BasePhase.has_unit_acted_this_phase): a unit has acted in the
## Movement phase once its move is over — a Normal / Advance / Fall Back move
## ended with End This Unit's Move (CONFIRM_UNIT_MOVE), it Remained Stationary,
## or it arrived from reserves (ingress); each sets flags.moved. Only the
## active player's units count: an opponent's flags.moved is left over from
## its own turn (cleared when that player's next turn starts). A unit still
## moving (movement_active, not confirmed) has not acted yet.
func has_unit_acted_this_phase(unit_id: String) -> bool:
	return _t09_is_active_players(unit_id) and _t09_unit_flag(unit_id, "moved")

## 09.02 MOVE UNITS: "When the Move Units step ends, the active player must
## have selected all of their units to make a move with ... every unit in
## their army will have been selected to make a move, even if it is to remain
## stationary." The ONE authoritative list of the player's units that have not
## been selected to move this phase — used by END_MOVEMENT (which resolves
## each of them as Remain Stationary, 09.04: ELIGIBLE IF any unit), the
## end-of-phase UI hint, and the multiplayer END_MOVEMENT path.
##
## Covers alive units ON THE BATTLEFIELD (deployed, not embarked) with no
## flags.moved and no move in progress. Excluded:
##   - attached CHARACTERs — they move with (and inherit the flags of) their
##     bodyguard;
##   - AIRCRAFT — only eligible to make an ingress move (23.02), never to
##     remain stationary;
##   - units in strategic reserves / embarked — selecting them to remain
##     stationary leaves them where they are and changes no state.
func get_units_requiring_selection(player: int) -> Array:
	var out: Array = []
	var units: Dictionary = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if int(unit.get("owner", 0)) != player:
			continue
		if _is_unit_destroyed_check(unit):
			continue
		if int(unit.get("status", 0)) != GameStateData.UnitStatus.DEPLOYED:
			continue
		if unit.get("embarked_in", null) != null:
			continue
		var attached_to = unit.get("attached_to", null)
		if attached_to != null and str(attached_to) != "":
			continue
		if "AIRCRAFT" in unit.get("meta", {}).get("keywords", []):
			continue
		var flags: Dictionary = unit.get("flags", {})
		if flags.get("moved", false) or flags.get("movement_active", false):
			continue
		if active_moves.has(unit_id):
			continue
		out.append(unit_id)
	return out

## The diffs END_MOVEMENT applies so that every unit still requiring selection
## (09.02) is selected and makes a Remain Stationary move (09.04) — e.g. so an
## untouched unit keeps its [HEAVY] / indirect-fire stationary benefits, which
## it lost while it was simply left unselected.
func get_end_movement_remain_stationary_changes(player: int) -> Array:
	var changes: Array = []
	for unit_id in get_units_requiring_selection(player):
		var unit = GameState.state.units[unit_id]
		log_phase_message("[09.02] %s was not selected to move — it remains stationary (09.04)" % unit.get("meta", {}).get("name", unit_id))
		changes.append_array(_remain_stationary_changes(unit_id, unit))
	return changes

func _validate_lock_movement_mode(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["Unit has not begun movement"]}
	
	if active_moves[unit_id].get("mode_locked", false):
		return {"valid": false, "errors": ["Movement mode already locked"]}
	
	return {"valid": true}

func _process_lock_movement_mode(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var mode = action.get("payload", {}).get("mode", "")
	
	if active_moves.has(unit_id):
		active_moves[unit_id]["mode_locked"] = true
		if mode != "":
			active_moves[unit_id]["mode"] = mode
		
		emit_signal("movement_mode_locked", unit_id, active_moves[unit_id]["mode"])
		log_phase_message("Locked movement mode for %s: %s" % [get_unit(unit_id).get("meta", {}).get("name", unit_id), active_moves[unit_id]["mode"]])
	
	return create_result(true, [])

func _validate_set_advance_bonus(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["Unit has not begun movement"]}
	
	if active_moves[unit_id].get("mode", "") != "ADVANCE":
		return {"valid": false, "errors": ["Unit is not advancing"]}
	
	return {"valid": true}

func _process_set_advance_bonus(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var bonus = action.get("payload", {}).get("bonus", 0)
	
	if active_moves.has(unit_id):
		active_moves[unit_id]["advance_roll"] = bonus
		var unit = get_unit(unit_id)
		var base_move = get_unit_movement(unit)
		active_moves[unit_id]["move_cap_inches"] = base_move + bonus
		
		log_phase_message("Set advance bonus for %s: +%d\" (total: %d\")" % [
			unit.get("meta", {}).get("name", unit_id),
			bonus,
			active_moves[unit_id]["move_cap_inches"]
		])
	
	return create_result(true, [])

# ============================================================================
# Codex: Adeptus Custodes (WP-C5, CustodesCodex11e.gd) — unit_selected_to_ingress
# (GOLDEN LIGHT OF THE MOIRAIDES). Main sends CUS11E_SELECT_INGRESS_UNIT when a
# reserve unit whose owner has such a stratagem is picked for placement, and
# starts the placement on cus11e_ingress_unit_ready (at once, or when the
# window closes). PLACE_REINFORCEMENT of a unit that was not asked (AI, direct
# dispatch) opens the window itself; a human decision holds the placement and
# the window's answer applies it.
# ============================================================================

signal cus11e_ingress_unit_ready(unit_id: String)

var _cus11e_ingress_asked: Dictionary = {}       # unit_id -> true: its window was opened this phase
var _cus11e_held_ingress_action: Dictionary = {} # PLACE_REINFORCEMENT held behind the window

func _cus11e_validate_select_ingress(action: Dictionary) -> Dictionary:
	var unit_id := str(action.get("unit_id", ""))
	var unit := get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}
	if int(unit.get("status", 0)) != GameStateData.UnitStatus.IN_RESERVES:
		return {"valid": false, "errors": ["%s is not in reserves" % unit_id]}
	if int(unit.get("owner", 0)) != get_current_player():
		return {"valid": false, "errors": ["%s does not belong to the active player" % unit_id]}
	return {"valid": true, "errors": []}

func _cus11e_process_select_ingress(action: Dictionary) -> Dictionary:
	var unit_id := str(action.get("unit_id", ""))
	if _cus11e_ingress_asked.has(unit_id):
		emit_signal("cus11e_ingress_unit_ready", unit_id)
		return create_result(true, [], "", {"cus11e_ingress_unit_ready": unit_id})
	_cus11e_ingress_asked[unit_id] = true
	var owner := int(get_unit(unit_id).get("owner", get_current_player()))
	if open_stratagem_window(owner, "unit_selected_to_ingress", {"phase": "movement", "unit_id": unit_id}, "_cus11e_resume_after_ingress_window"):
		log_phase_message("Waiting for Player %d's unit_selected_to_ingress stratagem decision (%s)" % [owner, unit_id])
		return create_result(true, consume_window_diffs())
	var res := create_result(true, consume_window_diffs(), "", {"cus11e_ingress_unit_ready": unit_id})
	emit_signal("cus11e_ingress_unit_ready", unit_id)
	return res

func _cus11e_resume_after_ingress_window(ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	var unit_id := str(ctx.get("unit_id", ""))
	if not _cus11e_held_ingress_action.is_empty() and str(_cus11e_held_ingress_action.get("unit_id", "")) == unit_id:
		var held := _cus11e_held_ingress_action
		_cus11e_held_ingress_action = {}
		log_phase_message("unit_selected_to_ingress answered — placing the held reinforcement %s" % unit_id)
		return _process_place_reinforcement(held)
	emit_signal("cus11e_ingress_unit_ready", unit_id)
	return create_result(true, [], "", {"cus11e_ingress_unit_ready": unit_id})

## {} = place now; otherwise the result of the action that paused for the window.
func _cus11e_ingress_window_before_placement(action: Dictionary) -> Dictionary:
	var unit_id := str(action.get("unit_id", ""))
	if GameConstants.edition < 11 or unit_id == "" or _cus11e_ingress_asked.has(unit_id):
		return {}
	_cus11e_ingress_asked[unit_id] = true
	var owner := int(get_unit(unit_id).get("owner", get_current_player()))
	if open_stratagem_window(owner, "unit_selected_to_ingress", {"phase": "movement", "unit_id": unit_id}, "_cus11e_resume_after_ingress_window"):
		_cus11e_held_ingress_action = action.duplicate(true)
		log_phase_message("Reinforcement %s held — waiting for Player %d's unit_selected_to_ingress decision" % [unit_id, owner])
		return create_result(true, consume_window_diffs())
	var sync := consume_window_diffs()
	if sync.is_empty():
		return {}
	# AI decision made synchronously: place now with the stratagem's diffs first.
	var placed := _process_place_reinforcement(action)
	if placed.get("success", false):
		var merged: Array = sync.duplicate()
		merged.append_array(placed.get("changes", []))
		placed["changes"] = merged
	return placed

func _validate_place_reinforcement(action: Dictionary) -> Dictionary:
	"""Validate placing a reserve unit onto the battlefield during the Reinforcements step"""
	var errors = []

	var required_fields = ["unit_id", "model_positions"]
	for field in required_fields:
		if not action.has(field):
			errors.append("Missing required field: " + field)

	if errors.size() > 0:
		return {"valid": false, "errors": errors}

	var unit_id = action.unit_id
	var model_positions = action.model_positions

	# Check if unit exists and is in reserves
	var unit = get_unit(unit_id)
	if unit.is_empty():
		errors.append("Unit not found: " + unit_id)
		return {"valid": false, "errors": errors}

	if unit.get("status", 0) != GameStateData.UnitStatus.IN_RESERVES:
		errors.append("Unit is not in reserves: " + unit_id)
		return {"valid": false, "errors": errors}

	# Check unit belongs to active player
	var active_player = get_current_player()
	if unit.get("owner", 0) != active_player:
		errors.append("Unit does not belong to active player")
		return {"valid": false, "errors": errors}

	# Check battle round - reserves can only arrive from Turn 2 onwards
	# (Codex: Adeptus Custodes (11e) Lightning Descent: "In your first Movement
	# phase, this unit can make an ingress move" — WP-C46; WP-O5 Impulsive Recon:
	# that ORKS AIRCRAFT can make an ingress move in its owner's first Movement phase.)
	var battle_round = GameState.get_battle_round()
	# WP-S4 HIGH KING OF FENRIS (Space Wolves, Logan Grimnar): this unit's ingress move treats the battle round as one higher.
	battle_round = _sw11e_abilities().ingress_battle_round(unit, battle_round)
	# WP-M4a DROP POD ASSAULT: "In your first Movement phase, this unit can make an ingress move."
	if battle_round < 2 and not _cus11e_det().can_ingress_first_round(unit) and not load("res://scripts/codex/orks/OrkEnhancements11e.gd").allows_first_round_ingress(unit) \
			and not load("res://scripts/codex/space_marines/SMDetachmentsB.gd").can_ingress_first_round(unit) \
			and not _sm11e_abilities_a().can_ingress_first_round(unit):  # WP-M2b Corporeum Reliquary / WP-M4a Drop Pod Assault (Codex: Space Marines 11e)
		errors.append("Reserves cannot arrive until Battle Round 2 (currently Round %d)" % battle_round)
		return {"valid": false, "errors": errors}

	var reserve_type = unit.get("reserve_type", "strategic_reserves")

	# P2-80: Balance Dataslate — if a unit with Deep Strike arrives from Strategic Reserves,
	# the player can choose to use Deep Strike rules OR Strategic Reserves rules.
	# The chosen placement_type overrides the reserve_type for validation purposes.
	var placement_type = action.get("placement_type", reserve_type)
	if placement_type == "deep_strike" and reserve_type == "strategic_reserves":
		# Verify the unit actually has Deep Strike ability before allowing DS placement
		if not GameState.unit_has_deep_strike(unit_id):
			errors.append("Unit does not have Deep Strike ability — cannot use Deep Strike placement rules")
			return {"valid": false, "errors": errors}
		DebugLogger.info(str("MovementPhase: P2-80 — Unit %s using Deep Strike placement rules (from Strategic Reserves)" % unit.get("meta", {}).get("name", unit_id)))

	# The whole arriving set-up: bodyguard + every attached CHARACTER coming in
	# with it. The leader's models are validated by the SAME rules as the squad's
	# (they used to bypass every check below and get teleported in unvalidated).
	var arrival_groups = _collect_arrival_groups(unit, unit_id, model_positions if model_positions is Array else [], action.get("model_rotations", []), action)

	# Set-up overlap gate (03.02) — applies at every edition and must run
	# BEFORE the 11e ingress branch below, which returns early. Without this,
	# arriving models could legally be stacked on top of models already on
	# the board (or on each other / on walls).
	if model_positions is Array:
		var setup_overlap = _validate_reinforcement_setup_overlaps(arrival_groups)
		if not setup_overlap.valid:
			return setup_overlap

	# ISS-060 step 2 (11e 20.04/24.09): reinforcements arrive via an
	# INGRESS MOVE — set-up validation through the template: wholly
	# within 6\" of a battlefield edge (lifted by Deep Strike), more than
	# 8\" from all enemies (vs 10e's 9\"), and not in the opponent's
	# deployment zone before battle round 3.
	if GameConstants.edition >= 11:
		var ingress_tmpl = MoveTypes.get_type("ingress")
		var pos_vecs: Array = []
		# Parallel to pos_vecs: the arriving model's own base data, so the
		# opponent-DZ ban can be tested against the real base rather than the
		# centre point (20.04 bars models set up "within" that zone).
		var pos_models: Array = []
		for g in arrival_groups:
			var g_models: Array = g["unit"].get("models", [])
			var g_rotations: Array = g.get("rotations", [])
			for pi in range(g["positions"].size()):
				var p = g["positions"][pi]
				if p == null:
					continue
				var pv = _reinforcement_pos_to_vec2(p)
				if pv != null:
					pos_vecs.append(pv)
					var md: Dictionary = (g_models[pi] as Dictionary).duplicate() if pi < g_models.size() and g_models[pi] is Dictionary else {}
					if pi < g_rotations.size() and g_rotations[pi] != null:
						md["rotation"] = float(g_rotations[pi])
					pos_models.append(md)
		# A12 (20.04): supply the opponent's deployment-zone polygon (px) so the
		# "not in opponent DZ before battle round 3" ban is actually enforced
		# (previously omitted, leaving the check inert).
		#
		# NOTE (pre-existing, unrelated to the ban itself): the OA-27 Outflank
		# bypass below lives only on the legacy pre-11e branch, which this early
		# return makes unreachable — so at edition 11 an Outflank unit is NOT
		# exempted from the opponent-DZ ban. Left as-is deliberately: the only
		# datasheet carrying Outflank in data/40kdc/abilities.json is flagged
		# "pre-launch-provisional", so granting the exemption at 11e is a rules
		# call for a human, not something to infer here.
		var _opp_zone_px := GameState.get_deployment_zone_poly_px(3 - active_player)
		var ingress_check = ingress_tmpl.validate_setup(unit_id, GameState.state, pos_vecs, {
			"battle_round": battle_round,
			"deep_strike": placement_type == "deep_strike",
			"board_size_inches": Vector2(GameState.state.board.size.width, GameState.state.board.size.height),
			"opponent_zone": _opp_zone_px,
			"models": pos_models,
		})
		if not ingress_check.valid:
			return {"valid": false, "errors": ingress_check.errors}
		log_phase_message("[11e] Ingress set-up validated for %s (%s, round %d)" % [unit_id, placement_type, battle_round])
		return {"valid": true, "errors": []}

	# Validate model positions — for the whole arriving set-up (bodyguard AND any
	# attached CHARACTER coming in with it).
	if model_positions is Array:
		var board_width = GameState.state.board.size.width  # 44 inches
		var board_height = GameState.state.board.size.height  # 60 inches
		var px_per_inch = 40.0

		for g in arrival_groups:
			var g_unit_id = str(g["unit_id"])
			var g_models = g["unit"].get("models", [])
			# The bodyguard keeps the bare "Model N" wording; a leader's models are
			# named so the player can tell which model of the arrival is illegal.
			var g_label = "" if g_unit_id == unit_id else "%s " % g["unit"].get("meta", {}).get("name", g_unit_id)
			for i in range(g["positions"].size()):
				var pos = _reinforcement_pos_to_vec2(g["positions"][i])
				if pos == null:
					continue

				var pos_inches_x = pos.x / px_per_inch
				var pos_inches_y = pos.y / px_per_inch

				# All reinforcements must be on the board
				if pos_inches_x < 0 or pos_inches_x > board_width or pos_inches_y < 0 or pos_inches_y > board_height:
					errors.append("%sModel %d: position is off the board" % [g_label, i])
					continue

				# Must be >9" from all enemy models (edge-to-edge)
				var model_data = g_models[i] if i < g_models.size() else {}
				var model_base_mm = model_data.get("base_mm", 32)
				var model_radius_inches = (model_base_mm / 2.0) / 25.4  # mm to inches

				var enemy_positions = GameState.get_enemy_model_positions(active_player)
				for enemy in enemy_positions:
					var enemy_pos_px = Vector2(enemy.x, enemy.y)
					var enemy_radius_inches = (enemy.base_mm / 2.0) / 25.4
					var dist_px = pos.distance_to(enemy_pos_px)
					var dist_inches = dist_px / px_per_inch
					# Edge-to-edge distance: center distance minus both radii
					var edge_dist = dist_inches - model_radius_inches - enemy_radius_inches
					if edge_dist < GameConstants.reinforcement_min_enemy_distance_inches():
						errors.append("%sModel %d: must be >%.0f\" from enemy models (currently %.1f\")" % [g_label, i, GameConstants.reinforcement_min_enemy_distance_inches(), edge_dist])
						break

				# Strategic Reserves: must be within 6" of a battlefield edge
				# P2-80: Use placement_type (which may override reserve_type) for validation
				if placement_type == "strategic_reserves":
					# 20.04 (and 10e's identical wording): set up WHOLLY within 6"
					# of a battlefield edge — the whole base, not the centre dot.
					var dist_to_left = pos_inches_x
					var dist_to_right = board_width - pos_inches_x
					var dist_to_top = pos_inches_y
					var dist_to_bottom = board_height - pos_inches_y
					var min_edge_dist = min(dist_to_left, dist_to_right, dist_to_top, dist_to_bottom)

					if not _wholly_within_setup_distance(pos, model_data, g["rotations"], i, board_width, board_height):
						errors.append("%sModel %d: Strategic Reserves must be set up wholly within 6\" of a battlefield edge (base reaches %.1f\")" % [g_label, i, min_edge_dist + model_radius_inches])

					# 20.04: before the THIRD battle round, no model may be set up
					# within the opponent's deployment zone (unless the unit has
					# Outflank — OA-27). Phrased as the rule is, not as `== 2`.
					if GameState.ingress_opponent_dz_ban_applies(battle_round, false):
						var _ability_mgr_outflank = get_node_or_null("/root/UnitAbilityManager")
						var _has_outflank = _ability_mgr_outflank and _ability_mgr_outflank.has_outflank(unit_id)
						if not _has_outflank:
							# "within" (not "wholly within") the zone — a base
							# straddling the boundary is inside it.
							var dz_probe = _dz_probe_model(model_data, pos, g["rotations"], i)
							if Measurement.model_overlaps_polygon(dz_probe, GameState.get_deployment_zone_poly_px(3 - active_player)):
								errors.append("%sModel %d: Strategic Reserves cannot arrive in the opponent's deployment zone before battle round 3" % [g_label, i])
						else:
							DebugLogger.info(str("MovementPhase: OA-27 Outflank — unit %s bypasses opponent deployment zone restriction" % unit_id))

				# Deep Strike: can be placed anywhere on the board (>9" check already done above)
				# No additional restrictions for deep strike placement

				# Omni-scramblers: cannot be set up within 12" of enemy units with Omni-scramblers
				var omni_positions = GameState.get_omni_scrambler_positions(active_player)
				for omni in omni_positions:
					var omni_pos_px = Vector2(omni.x, omni.y)
					var omni_radius_inches = (omni.base_mm / 2.0) / 25.4
					var dist_px = pos.distance_to(omni_pos_px)
					var dist_inches = dist_px / px_per_inch
					var edge_dist = dist_inches - model_radius_inches - omni_radius_inches
					if edge_dist < 12.0:
						errors.append("%sModel %d: cannot be set up within 12\" of enemy Omni-scramblers (%s) (currently %.1f\")" % [g_label, i, omni.get("unit_name", "unknown"), edge_dist])
						break

	# Check unit coherency: reinforcement models must maintain 2" horizontal and 5" vertical coherency
	if errors.is_empty():
		var final_models = []
		var unit_models = unit.get("models", [])
		for i in range(model_positions.size()):
			if model_positions[i] == null:
				continue
			if i >= unit_models.size():
				break
			if not unit_models[i].get("alive", true):
				continue
			var model_at_pos = unit_models[i].duplicate()
			model_at_pos["position"] = model_positions[i]
			final_models.append(model_at_pos)

		var coherency_result = _check_models_coherency(final_models)
		if not coherency_result.valid:
			errors.append_array(coherency_result.errors)

	return {"valid": errors.size() == 0, "errors": errors}

## Build a positioned model dict for a base-aware deployment-zone test: the
## arriving model's base data at the proposed px position, with its rotation
## (oval/rectangular bases care). Fed to Measurement.model_overlaps_polygon.
## 20.04: "Set up your unit WHOLLY within the set-up distance of one or more
## battlefield edges." Tested as containment in each edge's 6" band so rotated
## oval/rectangular bases go through the same shape code as every other zone
## check, rather than as a centre-point distance that ignored the base entirely.
func _wholly_within_setup_distance(pos: Vector2, model_data: Dictionary, rotations: Array, index: int, board_w_inches: float, board_h_inches: float) -> bool:
	var probe := _dz_probe_model(model_data, pos, rotations, index)
	var w: float = board_w_inches * 40.0
	var h: float = board_h_inches * 40.0
	var b: float = 6.0 * 40.0
	var bands := [
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, b), Vector2(0, b)]),
		PackedVector2Array([Vector2(0, h - b), Vector2(w, h - b), Vector2(w, h), Vector2(0, h)]),
		PackedVector2Array([Vector2(0, 0), Vector2(b, 0), Vector2(b, h), Vector2(0, h)]),
		PackedVector2Array([Vector2(w - b, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - b, h)]),
	]
	var rot: float = float(probe.get("rotation", 0.0))
	for band in bands:
		if Measurement.shape_wholly_in_polygon(pos, probe, rot, band):
			return true
	return false

func _dz_probe_model(model_data: Dictionary, pos: Vector2, rotations: Array, index: int) -> Dictionary:
	var probe: Dictionary = model_data.duplicate() if model_data is Dictionary else {}
	probe["position"] = pos
	if index < rotations.size() and rotations[index] != null:
		probe["rotation"] = float(rotations[index])
	return probe

func _validate_reinforcement_setup_overlaps(groups: Array) -> Dictionary:
	# 03.02: a unit that is SET UP (reinforcements, Rapid Ingress) is placed
	# like any other set-up — its models may not overlap any base already on
	# the board, may not overlap each other, and may not sit on a wall.
	# The 11e ingress template (IngressMove.validate_setup) only enforces
	# distance rules, and the pre-11e inline checks never covered overlap, so
	# a scripted/AI PLACE_REINFORCEMENT could stack arriving models on top of
	# units already on the board. The human placement UI blocks this
	# client-side, which is why only AI games ever showed the stacks.
	#
	# `groups` is the whole arriving set-up — the bodyguard plus any attached
	# CHARACTER arriving with it (see _collect_arrival_groups). They are checked
	# as ONE set-up so the leader can neither land on the squad it joins nor on
	# a unit already deployed, and every arriving unit is skipped when scanning
	# the board (their own models are still in reserves anyway).
	var errors: Array = []
	var arriving_ids := {}
	for g in groups:
		arriving_ids[str(g["unit_id"])] = true
	var placed: Array = []
	for g in groups:
		var unit_id = str(g["unit_id"])
		var unit_models = g["unit"].get("models", [])
		var unit_keywords = g["unit"].get("meta", {}).get("keywords", [])
		var model_positions: Array = g["positions"]
		var model_rotations: Array = g["rotations"]
		for i in range(model_positions.size()):
			if i >= unit_models.size():
				break
			var pos = model_positions[i]
			if pos == null or not unit_models[i].get("alive", true):
				continue
			var pos_vec = _reinforcement_pos_to_vec2(pos)
			if pos_vec == null:
				continue
			var check_model = unit_models[i].duplicate()
			check_model["position"] = pos_vec
			if i < model_rotations.size() and model_rotations[i] != null:
				check_model["rotation"] = float(model_rotations[i])
			var model_label = str(check_model.get("id", "m%d" % (i + 1)))

			# Against every model already on the board (any owner). Embarked units
			# carry null positions and are skipped by the position check.
			var found_overlap := false
			for other_id in game_state_snapshot.get("units", {}):
				if arriving_ids.has(other_id):
					continue
				var other_unit = game_state_snapshot.units[other_id]
				for om in other_unit.get("models", []):
					if not om.get("alive", true) or om.get("position", null) == null:
						continue
					if Measurement.models_overlap(check_model, om) and not _is_touching_within_tolerance(check_model, om):
						errors.append("Model %s cannot be set up overlapping a model of %s" % [model_label, other_id])
						found_overlap = true
						break
				if found_overlap:
					break

			# Against the other arriving models of this same set-up.
			for pm in placed:
				if Measurement.models_overlap(check_model, pm) and not _is_touching_within_tolerance(check_model, pm):
					errors.append("Models %s and %s of the arriving unit cannot be set up overlapping each other" % [model_label, str(pm.get("id", "?"))])
					break

			# Walls: the set-up position must be clear of walls the unit can't occupy.
			if Measurement.model_overlaps_any_wall(check_model, unit_keywords):
				errors.append("Model %s cannot be set up overlapping a wall" % model_label)

			# Issue #87 parity with the placement UI: no part of a base may hang off
			# the battlefield. The 11e ingress branch returns on the template's
			# verdict and IngressMove.validate_setup does not test board bounds at
			# all for a Deep Strike (its 6"-from-edge rule is lifted), so nothing
			# else checks this engine-side.
			# Deliberately limited to the attached leaders for now: the primary
			# unit's positions can come from AIDecisionMaker, whose edge margin is a
			# flat 30px rather than the model's own base radius, so a wide-based
			# unit arriving on the edge strip would start failing validation.
			# Widening this to the whole set-up means making that margin
			# base-aware first.
			if g.get("check_board_bounds", false) and Measurement.model_outside_board(pos_vec, check_model):
				errors.append("Model %s cannot be set up off the battlefield" % model_label)

			placed.append(check_model)
	return {"valid": errors.is_empty(), "errors": errors}

# Positions reach the phase as Vector2 (placement UI), Dictionary (replayed /
# networked actions) or [x, y] (scripted tests). Returns null for anything else.
func _reinforcement_pos_to_vec2(pos) -> Variant:
	if pos is Vector2:
		return pos
	if pos is Dictionary and pos.has("x") and pos.has("y"):
		return Vector2(float(pos["x"]), float(pos["y"]))
	if pos is Array and pos.size() >= 2:
		return Vector2(float(pos[0]), float(pos[1]))
	return null

# An arriving set-up is the bodyguard PLUS every attached CHARACTER still in
# reserves — 11e 24.10: they are one Attached unit and are set up together.
# Returns [{unit_id, unit, positions, rotations}], the bodyguard first. Character
# positions come from the action when the player placed them (see
# Main._split_placement_positions); an AI/scripted arrival that omits them gets
# an empty positions array here and is auto-placed at process time.
func _collect_arrival_groups(unit: Dictionary, unit_id: String, model_positions: Array, model_rotations: Array, action: Dictionary) -> Array:
	var groups: Array = [{
		"unit_id": unit_id,
		"unit": unit,
		"positions": model_positions,
		"rotations": model_rotations,
		"check_board_bounds": false,  # see _validate_reinforcement_setup_overlaps
	}]
	var char_positions_by_id = action.get("character_model_positions", {})
	var char_rotations_by_id = action.get("character_model_rotations", {})
	for char_id in unit.get("attachment_data", {}).get("attached_characters", []):
		var char_unit = get_unit(char_id)
		if char_unit.is_empty():
			continue
		if char_unit.get("status", 0) != GameStateData.UnitStatus.IN_RESERVES:
			continue
		groups.append({
			"unit_id": str(char_id),
			"unit": char_unit,
			"positions": char_positions_by_id.get(char_id, []),
			"rotations": char_rotations_by_id.get(char_id, []),
			"check_board_bounds": true,
		})
	return groups

# Positioned copies of the arriving unit's models — the bases this set-up has
# already committed to the table. Used as extra collision targets when a leader
# has to be auto-placed (its squad's models are still "in reserves" in the
# snapshot, so scanning the board alone would not see them).
func _arrival_footprint(unit: Dictionary, model_positions: Array, model_rotations: Array) -> Array:
	var out: Array = []
	var models = unit.get("models", [])
	for i in range(model_positions.size()):
		if i >= models.size():
			break
		if not models[i].get("alive", true):
			continue
		var pv = _reinforcement_pos_to_vec2(model_positions[i])
		if pv == null:
			continue
		var m = models[i].duplicate()
		m["position"] = pv
		if i < model_rotations.size() and model_rotations[i] != null:
			m["rotation"] = float(model_rotations[i])
		out.append(m)
	return out

# Fallback spot for an attached CHARACTER whose position the action did not
# carry (AI / scripted arrivals). Spirals outwards from the squad's centre and
# returns the first ring position whose base is clear of every model already on
# the board, of the models arriving with it, and of walls. The old behaviour —
# a flat "first model + 1 inch to the right" — dropped the leader straight on
# top of its own squad, which is what put stacked tokens on the board.
func _auto_place_attached_character_model(char_model: Dictionary, char_unit: Dictionary, model_positions: Array, arrival_footprint: Array) -> Variant:
	var anchor: Variant = null
	var sum := Vector2.ZERO
	var n := 0
	for p in model_positions:
		var pv = _reinforcement_pos_to_vec2(p)
		if pv != null:
			sum += pv
			n += 1
	if n > 0:
		anchor = sum / float(n)
	if anchor == null:
		return null

	var keywords = char_unit.get("meta", {}).get("keywords", [])
	var owner = int(char_unit.get("owner", 0))
	var step = max(Measurement.base_radius_px(char_model.get("base_mm", 32)) * 2.0, 40.0)
	var candidate = char_model.duplicate()
	for ring in range(1, 13):
		var radius = step * ring
		for spoke in range(12):
			var angle = TAU * float(spoke) / 12.0
			candidate["position"] = anchor + Vector2(cos(angle), sin(angle)) * radius
			if _auto_placement_spot_is_clear(candidate, arrival_footprint, keywords, owner):
				return candidate["position"]
	# Nothing clear within ~12 rings — fall back to the old offset so the leader
	# still arrives rather than being silently left in reserves.
	log_phase_message("WARNING: no clear auto-placement spot for attached character; using squad centre offset")
	return anchor + Vector2(step, 0.0)

func _auto_placement_spot_is_clear(candidate: Dictionary, arrival_footprint: Array, keywords: Array, owner: int) -> bool:
	for other in arrival_footprint:
		if Measurement.models_overlap(candidate, other):
			return false
	# 20.04/24.09: an arriving model must also stay outside the enemy exclusion,
	# so the auto spot is a legal set-up and not merely a non-overlapping one.
	var min_enemy_px = Measurement.inches_to_px(GameConstants.reinforcement_min_enemy_distance_inches())
	for other_id in game_state_snapshot.get("units", {}):
		var other_unit = game_state_snapshot.units[other_id]
		var is_enemy = int(other_unit.get("owner", 0)) != owner
		for om in other_unit.get("models", []):
			if not om.get("alive", true) or om.get("position", null) == null:
				continue
			if Measurement.models_overlap(candidate, om):
				return false
			if is_enemy and Measurement.model_to_model_distance_px(candidate, om) <= min_enemy_px:
				return false
	if Measurement.model_overlaps_any_wall(candidate, keywords):
		return false
	if Measurement.model_outside_board(candidate["position"], candidate):
		return false
	return true

func _process_place_reinforcement(action: Dictionary) -> Dictionary:
	"""Process placing a reserve unit onto the battlefield"""
	# Codex: Adeptus Custodes GOLDEN LIGHT OF THE MOIRAIDES (CustodesCodex11e.gd):
	# unit_selected_to_ingress opens before the unit is set up — the UI asks
	# first (CUS11E_SELECT_INGRESS_UNIT); an AI / direct placement asks here.
	var cus11e_held := _cus11e_ingress_window_before_placement(action)
	if not cus11e_held.is_empty():
		return cus11e_held
	var unit_id = action.unit_id
	var model_positions = action.model_positions
	var model_rotations = action.get("model_rotations", [])
	var changes = []

	# Update model positions
	for i in range(model_positions.size()):
		var pos = model_positions[i]
		if pos != null:
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [unit_id, i],
				"value": {"x": pos.x, "y": pos.y}
			})
			if i < model_rotations.size() and model_rotations[i] != null:
				changes.append({
					"op": "set",
					"path": "units.%s.models.%d.rotation" % [unit_id, i],
					"value": model_rotations[i]
				})

	# Update unit status from IN_RESERVES to DEPLOYED
	changes.append({
		"op": "set",
		"path": "units.%s.status" % unit_id,
		"value": GameStateData.UnitStatus.DEPLOYED
	})

	# OA-23: Track the battle round this unit arrived from reserves (for Plummeting Descent)
	changes.append({
		"op": "set",
		"path": "units.%s.arrived_from_reserves_turn" % unit_id,
		"value": GameState.get_battle_round()
	})

	# ISS-060 step 2 (11e 20.04): the arrival is an INGRESS MOVE — the
	# template's AFTER effects apply (arrived_from_reserves +
	# no-other-moves-until-the-next-Charge-phase, so the unit CAN charge).
	if GameConstants.edition >= 11:
		changes.append_array(MoveTypes.get_type("ingress").after_moving_effects(unit_id, {}))
		log_phase_message("[11e] %s arrived via ingress move (may charge; no further moves this phase)" % unit_id)
		# WP-O5 Flyboss: friendly ORKS AIRCRAFT/DEFFKOPTAS within 6" are riled up.
		changes.append_array(load("res://scripts/codex/orks/OrkEnhancements11e.gd").on_ingress_move_ended(unit_id, model_positions))

	# Deploy attached characters that are also in reserves.
	# 11e 24.10: the leader and its bodyguard are ONE Attached unit, so they are
	# set up together. The placement UI now places the leader's model(s) itself
	# and ships them in `character_model_positions`; only AI / scripted arrivals
	# that omit them fall back to _auto_place_attached_character_model.
	var unit = get_unit(unit_id)
	var attachment_data = unit.get("attachment_data", {})
	var attached_chars = attachment_data.get("attached_characters", [])
	var char_model_positions = action.get("character_model_positions", {})
	var char_model_rotations = action.get("character_model_rotations", {})
	# Every base this set-up has already committed to the table — the arriving
	# squad plus any leader already positioned — so the fallback never drops a
	# leader on top of the unit it just joined.
	var arrival_footprint = _arrival_footprint(unit, model_positions, model_rotations)

	for char_id in attached_chars:
		var char_unit = get_unit(char_id)
		if char_unit.get("status", 0) != GameStateData.UnitStatus.IN_RESERVES:
			continue

		# Deploy the character — use provided positions or place near the bodyguard
		var char_positions = char_model_positions.get(char_id, [])
		var char_rotations = char_model_rotations.get(char_id, [])
		var char_models = char_unit.get("models", [])
		for ci in range(char_models.size()):
			var char_pos = null
			if ci < char_positions.size():
				char_pos = _reinforcement_pos_to_vec2(char_positions[ci])
			var char_rot = null
			if ci < char_rotations.size() and char_rotations[ci] != null:
				char_rot = float(char_rotations[ci])
			if char_pos == null:
				char_pos = _auto_place_attached_character_model(char_models[ci], char_unit, model_positions, arrival_footprint)
			if char_pos != null:
				changes.append({
					"op": "set",
					"path": "units.%s.models.%d.position" % [char_id, ci],
					"value": {"x": char_pos.x, "y": char_pos.y}
				})
				if char_rot != null:
					changes.append({
						"op": "set",
						"path": "units.%s.models.%d.rotation" % [char_id, ci],
						"value": char_rot
					})
				var footprint_model = char_models[ci].duplicate()
				footprint_model["position"] = char_pos
				if char_rot != null:
					footprint_model["rotation"] = char_rot
				arrival_footprint.append(footprint_model)

		changes.append({
			"op": "set",
			"path": "units.%s.status" % char_id,
			"value": GameStateData.UnitStatus.DEPLOYED
		})

		var char_name = char_unit.get("meta", {}).get("name", char_id)
		log_phase_message("Attached character %s arrived with bodyguard from reserves" % char_name)

	# Clear Acrobatic Escape reserves flag if set (Callidus Assassin returning from vanish)
	var unit_pre = get_unit(unit_id)
	if unit_pre.get("flags", {}).get("acrobatic_escape_reserves", false):
		changes.append({
			"op": "remove",
			"path": "units.%s.flags.acrobatic_escape_reserves" % unit_id
		})

	# Clear strategic reserves redeploy flag (From Golden Light, etc. returning from reserves)
	if unit_pre.get("flags", {}).get("strategic_reserves_redeploy", false):
		changes.append({
			"op": "remove",
			"path": "units.%s.flags.strategic_reserves_redeploy" % unit_id
		})

	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)

	# Update local snapshot
	if game_state_snapshot.has("units") and game_state_snapshot.units.has(unit_id):
		game_state_snapshot.units[unit_id]["status"] = GameStateData.UnitStatus.DEPLOYED
	for char_id in attached_chars:
		if game_state_snapshot.has("units") and game_state_snapshot.units.has(char_id):
			game_state_snapshot.units[char_id]["status"] = GameStateData.UnitStatus.DEPLOYED

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var reserve_type = unit.get("reserve_type", "strategic_reserves")
	var placement_type = action.get("placement_type", reserve_type)
	var type_label = "Deep Strike" if placement_type == "deep_strike" else "Strategic Reserves"
	# P2-80: Log when DS placement rules were chosen for a SR unit
	if placement_type != reserve_type:
		log_phase_message("Reinforcement arrived: %s via %s (chose %s rules from %s)" % [
			unit_name, type_label,
			"Deep Strike" if placement_type == "deep_strike" else "Strategic Reserves",
			"Strategic Reserves" if reserve_type == "strategic_reserves" else "Deep Strike"
		])
	else:
		log_phase_message("Reinforcement arrived: %s via %s" % [unit_name, type_label])

	# T7-39: Recheck objective control after reinforcement placement
	if MissionManager:
		MissionManager.call_deferred("check_all_objectives", false)

	# WP-M4a TELEPORT HOMER: the token this set-up used is removed.
	var sm_homer: Array = _sm11e_abilities_a().on_reinforcement_set_up(unit_id)
	if not sm_homer.is_empty():
		PhaseManager.apply_state_changes(sm_homer)
		changes.append_array(sm_homer)
	# WP-M4a DROP POD ASSAULT: the embarked units disembark as the Drop Pod lands
	# (the owner's sm11e_drop_pod_landed window) before the opponent reacts.
	var sm_dp := _sm11e_drop_pod_window(unit_id, changes)
	if not sm_dp.is_empty():
		return sm_dp

	# Codex: Orks (11e) enemy_ended_move: the arrival is an ingress move
	# (20.04). The opponent's window opens once the Fire Overwatch prompt
	# below has resolved (its decline / use paths open it), else right away.
	if GameConstants.edition >= 11:
		_ork11e_eem_pending = {"unit_id": unit_id, "move_type": "ingress"}
		_ork11e_pending_move_changes = []

	# P2-88: Check for Fire Overwatch opportunity after reinforcement is set up
	# Balance Dataslate timing: "just after an enemy unit is set up"
	var ow_result = _check_fire_overwatch_opportunity(unit_id, "reinforcement set up")
	if ow_result.triggered:
		var result = create_result(true, changes)
		result.merge(ow_result.result_extra)
		return result

	return _ork11e_with_enemy_ended_move(create_result(true, changes))

## WP-M4a DROP POD ASSAULT (SMAbilitiesA.drop_pod_landed): a Drop Pod with
## embarked units was just set up — open its owner's sm11e_drop_pod_landed
## window (the "Drop Pod Assault" card starts the assault-disembark follow-up;
## an AI owner decides and disembarks synchronously). {} = nothing to do (the
## caller continues its own set-up tail).
func _sm11e_drop_pod_window(unit_id: String, changes: Array) -> Dictionary:
	if GameConstants.edition < 11:
		return {}
	var dp: Dictionary = _sm11e_abilities_a().drop_pod_landed(unit_id)
	if dp.is_empty():
		return {}
	PhaseManager.apply_state_changes(dp.get("diffs", []))
	changes.append_array(dp.get("diffs", []))
	if (dp.get("units", []) as Array).is_empty():
		return {}
	var owner := int(get_unit(unit_id).get("owner", get_current_player()))
	if open_stratagem_window(owner, "sm11e_drop_pod_landed", {"phase": "movement", "unit_id": unit_id}, "_sm11e_resume_after_drop_pod_window"):
		log_phase_message("Drop Pod Assault: waiting for Player %d to disembark the units in %s" % [owner, unit_id])
		var paused: Array = changes.duplicate()
		paused.append_array(consume_window_diffs())
		return create_result(true, paused)
	changes.append_array(consume_window_diffs())
	return _sm11e_reinforcement_tail(unit_id, changes)

## Resume of the sm11e_drop_pod_landed window: the rest of the set-up (Fire
## Overwatch, the opponent's enemy_ended_move window).
func _sm11e_resume_after_drop_pod_window(ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	return _sm11e_reinforcement_tail(str(ctx.get("unit_id", "")), [])

## WP-M4a: the moving unit's start positions {model_id: {x, y}} (px) from the
## move's original_positions ("<unit>:<model>" keys) — JSON-safe window ctx.
func _sm11e_from_positions(unit_id: String, move_data: Dictionary) -> Dictionary:
	var out := {}
	var orig = move_data.get("original_positions", {})
	if typeof(orig) != TYPE_DICTIONARY:
		return out
	for k in orig:
		var parts := str(k).split(":")
		if parts.size() != 2 or parts[0] != unit_id:
			continue
		var p = orig[k]
		if p is Vector2:
			out[parts[1]] = {"x": p.x, "y": p.y}
		elif p is Dictionary:
			out[parts[1]] = {"x": float(p.get("x", 0.0)), "y": float(p.get("y", 0.0))}
	return out

## The tail of _process_place_reinforcement (same steps, in the same order).
func _sm11e_reinforcement_tail(unit_id: String, changes: Array) -> Dictionary:
	if GameConstants.edition >= 11:
		_ork11e_eem_pending = {"unit_id": unit_id, "move_type": "ingress"}
		_ork11e_pending_move_changes = []
	var ow_result = _check_fire_overwatch_opportunity(unit_id, "reinforcement set up")
	if ow_result.triggered:
		var result = create_result(true, changes)
		result.merge(ow_result.result_extra)
		return result
	return _ork11e_with_enemy_ended_move(create_result(true, changes))

func _process_end_movement(action: Dictionary) -> Dictionary:
	log_phase_message("=== PROCESSING END_MOVEMENT ===")

	# Clean up any stale movement_active flags (safety net for T2-12)
	var changes = []
	var current_player = get_current_player()
	# 09.02: the Move Units step may only end once every unit has been
	# selected to move. Every unit the player has not selected is selected
	# now and remains stationary (09.04) — the state reflects that move
	# instead of leaving the unit unselected.
	var rs_changes = get_end_movement_remain_stationary_changes(current_player)
	if not rs_changes.is_empty():
		PhaseManager.apply_state_changes(rs_changes)
		changes.append_array(rs_changes)
		# Multiplayer (RV-2: the host's END_MOVEMENT runs here): ship the
		# Remain Stationary diffs to the client BEFORE this phase can complete
		# — the phase change is broadcast as soon as phase_completed fires,
		# ahead of this action's result, and a client entering Shooting
		# without them reports a false desync (same pattern as PhaseManager's
		# Superior Creation revivals).
		var rs_nm = get_node_or_null("/root/NetworkManager")
		if rs_nm and rs_nm.has_method("is_networked") and rs_nm.is_networked() and rs_nm.is_host():
			rs_nm._broadcast_result_from_phase_manager({
				"success": true,
				"diffs": rs_changes.duplicate(true),
				"action_type": "END_MOVEMENT_REMAIN_STATIONARY"
			})
	var all_units = get_units_for_player(current_player)
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if unit.get("flags", {}).get("movement_active", false):
			log_phase_message("Cleaning up stale movement_active flag for unit %s" % unit_id)
			changes.append({
				"op": "remove",
				"path": "units.%s.flags.movement_active" % unit_id
			})

	# T4-7: Rapid Ingress, then phase completion. (The pre-codex Sawbonez /
	# Mekaniak / Grot Oiler end-of-movement prompts are gone — WP-O6.)
	return _continue_end_movement_rapid_ingress(changes)

func _process_desperate_escape(unit_id: String, move_data: Dictionary) -> Dictionary:
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	var changes = []
	var dice_rolls = []

	# FLY and TITANIC units skip Desperate Escape tests when Falling Back
	# 10e Rule: FLY units can move over enemy models without taking Desperate Escape tests
	# 10e Rule: TITANIC models do not take Desperate Escape tests when Falling Back
	var keywords = unit.get("meta", {}).get("keywords", [])
	if "FLY" in keywords or "TITANIC" in keywords:
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var skip_reason = "FLY" if "FLY" in keywords else "TITANIC"
		log_phase_message("Desperate Escape skipped for %s (%s keyword)" % [unit_name, skip_reason])
		return {"changes": [], "dice": []}

	# Determine which models need Desperate Escape tests
	var models_to_test = []
	
	if move_data.battle_shocked:
		# All models test if Battle-shocked
		for i in range(models.size()):
			var model = models[i]
			if model.get("alive", true):
				models_to_test.append({"index": i, "id": model.get("id", "m%d" % i)})
	else:
		# Only models that crossed enemies
		for model_move in move_data.model_moves:
			if model_move.crosses_enemy:
				var idx = _get_model_index(unit_id, model_move.model_id)
				if idx >= 0:
					models_to_test.append({"index": idx, "id": model_move.model_id})
	
	if models_to_test.is_empty():
		return {"changes": [], "dice": []}
	
	# Roll D6 for each model (with deterministic seed for multiplayer)
	var rng_seed = -1
	if has_node("/root/NetworkManager"):
		var net_mgr = get_node("/root/NetworkManager")
		if net_mgr.is_networked() and net_mgr.is_host():
			rng_seed = net_mgr.get_next_rng_seed()

	var rng_service = RulesEngine.RNGService.new(rng_seed)
	var casualties = 0
	var rolls = []

	# 10e Rule: Desperate Escape failure threshold
	# Normal: model destroyed on 1-2
	# Battle-shocked: model destroyed on 1-3
	var fail_threshold = 3 if move_data.battle_shocked else 2

	for model_data in models_to_test:
		var roll_result = rng_service.roll_d6(1)
		var roll = roll_result[0]
		rolls.append(roll)
		if roll <= fail_threshold:
			casualties += 1
	
	# Apply casualties (player chooses which models)
	# For MVP, remove the first N alive models
	var removed = 0
	for i in range(models.size()):
		if removed >= casualties:
			break
		if models[i].get("alive", true):
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.alive" % [unit_id, i],
				"value": false
			})
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.current_wounds" % [unit_id, i],
				"value": 0
			})
			removed += 1
	
	dice_rolls.append({
		"context": "desperate_escape",
		"n": models_to_test.size(),
		"rolls": rolls
	})
	
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	if casualties > 0:
		dice_log.append({
			"unit_id": unit_id,
			"unit_name": unit_name,
			"type": "Desperate Escape",
			"rolls": rolls,
			"result": "%d models lost" % casualties
		})
		var shocked_str = " (Battle-shocked, fail on 1-%d)" % fail_threshold if move_data.battle_shocked else ""
		log_phase_message("Desperate Escape: %s%s → rolls: %s → models lost: %d" % [unit_name, shocked_str, str(rolls), casualties])
	
	return {"changes": changes, "dice": dice_rolls}

# ============================================================================
# KRUMP AND RUN — REACTIVE MOVE AFTER FALL BACK (OA-8)
# ============================================================================
# Freebooter Krew – Strategic Ploy Stratagem (1 CP)
# WHEN: Your opponent's Movement phase, just after an enemy unit falls back.
# TARGET: One ORKS unit that was within engagement range of that enemy unit at
#         the start of the phase and is not within engagement range of one or more enemy units.
# EFFECT: Your unit can make a Normal move of up to 6".

func _compute_engagement_snapshot() -> Dictionary:
	"""Compute which units are engaged with which enemy units at the current moment.
	Returns { unit_id: [enemy_unit_ids] } for all deployed units in engagement."""
	var result = {}
	var units = game_state_snapshot.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if _is_unit_destroyed_check(unit):
			continue
		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
			continue

		var unit_owner = int(unit.get("owner", 0))
		var engaged_enemies = []

		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var pos = _get_model_position(model)
			if pos == null or pos == Vector2.ZERO:
				continue

			for enemy_unit_id in units:
				if enemy_unit_id == unit_id or enemy_unit_id in engaged_enemies:
					continue
				var enemy_unit = units[enemy_unit_id]
				if int(enemy_unit.get("owner", 0)) == unit_owner:
					continue
				if _is_unit_destroyed_check(enemy_unit):
					continue
				if enemy_unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
					continue

				var found_engagement = false
				for enemy_model in enemy_unit.get("models", []):
					if not enemy_model.get("alive", true):
						continue
					var enemy_pos = _get_model_position(enemy_model)
					if enemy_pos == null or enemy_pos == Vector2.ZERO:
						continue
					var effective_er = _get_effective_engagement_range(pos, enemy_pos)
					if Measurement.is_in_engagement_range_shape_aware(model, enemy_model, effective_er):
						engaged_enemies.append(enemy_unit_id)
						found_engagement = true
						break
				if found_engagement:
					break  # Already found engagement with this enemy, check next enemy unit

		if not engaged_enemies.is_empty():
			result[unit_id] = engaged_enemies

	return result

func _is_unit_engaged_for_player(unit_id: String, owner_player: int, snapshot_override: Dictionary = {}) -> bool:
	"""Check if a unit is in engagement range of any enemy unit.
	Uses owner_player to determine which units are enemies, instead of get_current_player()."""
	var check_snapshot = snapshot_override if not snapshot_override.is_empty() else game_state_snapshot
	var unit = check_snapshot.get("units", {}).get(unit_id, {})
	var models = unit.get("models", [])
	var units = check_snapshot.get("units", {})

	for model in models:
		if not model.get("alive", true):
			continue
		var pos = _get_model_position(model)
		if pos == null or pos == Vector2.ZERO:
			continue

		for enemy_unit_id in units:
			if enemy_unit_id == unit_id:
				continue
			var enemy_unit = units[enemy_unit_id]
			if int(enemy_unit.get("owner", 0)) == owner_player:
				continue  # Skip friendly units
			if _is_unit_destroyed_check(enemy_unit):
				continue
			for enemy_model in enemy_unit.get("models", []):
				if not enemy_model.get("alive", true):
					continue
				var enemy_pos = _get_model_position(enemy_model)
				if enemy_pos == null or enemy_pos == Vector2.ZERO:
					continue
				var effective_er = _get_effective_engagement_range(pos, enemy_pos)
				if Measurement.is_in_engagement_range_shape_aware(model, enemy_model, effective_er):
					return true

	return false

func _check_krump_and_run_opportunity(fell_back_unit_id: String, snapshot_override: Dictionary = {}) -> Dictionary:
	"""Check if any defending ORKS unit can use Krump and Run after an enemy falls back.
	Returns { triggered: bool, result_extra: Dictionary }."""
	var fell_back_unit = get_unit(fell_back_unit_id)
	var active_player = get_current_player()  # The player who fell back
	var defending_player = 2 if active_player == 1 else 1  # Potential Ork player

	var strat_manager = get_node_or_null("/root/StratagemManager")
	if not strat_manager:
		return {"triggered": false}

	# Find the reactive fall-back stratagem for the defending player:
	# KRUMP AND RUN (Freebooter Krew), ON TO DA NEXT (Taktikal Brigade) or
	# WHERE D'YA FINK YOU'RE GOING? (Da Big Hunt) — identical effect
	# (6" Normal move after an enemy Falls Back; per-unit targeting rules
	# differ and are enforced by can_use_stratagem below).
	var kar_strat_id = ""
	var kar_strat_name = "Krump and Run"
	for candidate in ["Krump and Run", "On to da Next", "Where D'ya Fink You're Going?"]:
		kar_strat_id = strat_manager.find_faction_stratagem_by_name(defending_player, candidate)
		# Codex: Orks (11e) WHERE D'YA FINK YOU'RE GOING? is NOT the old 10e
		# reactive 6" move — it is offered in the enemy_selected_to_fall_back
		# window (OrkCodexMovement). Skip every codex row here.
		if kar_strat_id != "" and Ork11eCodex.handles(strat_manager.get_stratagem(kar_strat_id)):
			kar_strat_id = ""
			continue
		if kar_strat_id != "":
			kar_strat_name = candidate
			break
	if kar_strat_id == "":
		return {"triggered": false}
	var kar_strat_type = str(strat_manager.get_stratagem(kar_strat_id).get("type", ""))

	# Check basic stratagem availability (CP, restrictions)
	var basic_check = strat_manager.can_use_stratagem(defending_player, kar_strat_id)
	if not basic_check.can_use:
		DebugLogger.info(str("MovementPhase: OA-8 Krump and Run not available: %s" % basic_check.reason))
		return {"triggered": false}

	var check_snapshot = snapshot_override if not snapshot_override.is_empty() else game_state_snapshot

	# Find eligible ORKS units
	var eligible = []
	var units = check_snapshot.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if int(unit.get("owner", 0)) != defending_player:
			continue
		if _is_unit_destroyed_check(unit):
			continue
		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
			continue

		# Must be ORKS keyword
		if not RulesEngine.unit_has_keyword(unit, "ORKS"):
			continue

		# Must have been in engagement with the fell-back unit at phase start
		if not _engagement_at_phase_start.has(unit_id):
			continue
		if fell_back_unit_id not in _engagement_at_phase_start[unit_id]:
			continue

		# Must NOT currently be in engagement with any enemy unit (freed from all combat)
		if _is_unit_engaged_for_player(unit_id, defending_player, check_snapshot):
			continue

		# Must not be battle-shocked
		if unit.get("flags", {}).get("battle_shocked", false) or unit.get("status_effects", {}).get("battle_shocked", false):
			continue

		# Check stratagem can be used for this specific target
		var check = strat_manager.can_use_stratagem(defending_player, kar_strat_id, unit_id)
		if not check.can_use:
			continue

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		eligible.append({"unit_id": unit_id, "unit_name": unit_name, "strat_name": kar_strat_name, "strat_type": kar_strat_type})

	if eligible.is_empty():
		DebugLogger.info(str("MovementPhase: OA-8 %s — no eligible ORKS units after %s fell back" % [kar_strat_name, fell_back_unit_id]))
		return {"triggered": false}

	# The reactive fall-back stratagem is available!
	_awaiting_krump_and_run = true
	_krump_and_run_player = defending_player
	_krump_and_run_eligible_units = eligible
	_krump_and_run_fell_back_unit_id = fell_back_unit_id
	_krump_and_run_strat_id = kar_strat_id
	_krump_and_run_strat_name = kar_strat_name

	var fell_back_name = fell_back_unit.get("meta", {}).get("name", fell_back_unit_id)
	log_phase_message("%s available for Player %d (%d eligible ORKS units) after %s fell back" % [kar_strat_name.to_upper(), defending_player, eligible.size(), fell_back_name])
	DebugLogger.info(str("MovementPhase: OA-8 %s opportunity — Player %d has %d eligible units" % [kar_strat_name, defending_player, eligible.size()]))

	emit_signal("krump_and_run_opportunity", defending_player, eligible, fell_back_unit_id)

	return {
		"triggered": true,
		"result_extra": {
			"trigger_krump_and_run": true,
			"awaiting_krump_and_run": true,
			"krump_and_run_player": defending_player,
			"krump_and_run_eligible_units": eligible,
			"krump_and_run_fell_back_unit_id": fell_back_unit_id,
		}
	}

func _validate_use_krump_and_run(action: Dictionary) -> Dictionary:
	"""Validate using the Krump and Run stratagem."""
	var errors = []

	if not _awaiting_krump_and_run:
		errors.append("Not awaiting Krump and Run decision")
		return {"valid": false, "errors": errors}

	var unit_id = action.get("payload", {}).get("unit_id", "")
	if unit_id.is_empty():
		errors.append("No unit specified for Krump and Run")
		return {"valid": false, "errors": errors}

	# Validate the unit is in the eligible list
	var found = false
	for eligible in _krump_and_run_eligible_units:
		if eligible.unit_id == unit_id:
			found = true
			break
	if not found:
		errors.append("Unit %s is not eligible for Krump and Run" % unit_id)
		return {"valid": false, "errors": errors}

	return {"valid": true, "errors": []}

func _process_use_krump_and_run(action: Dictionary) -> Dictionary:
	"""Process using Krump and Run — use stratagem and set up reactive Normal move."""
	var unit_id = action.get("payload", {}).get("unit_id", "")
	var player = _krump_and_run_player
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	# Use the stratagem via StratagemManager (deducts CP, records usage)
	var strat_manager = get_node_or_null("/root/StratagemManager")
	if strat_manager:
		var kar_strat_id = _krump_and_run_strat_id
		if kar_strat_id == "":
			kar_strat_id = strat_manager.find_faction_stratagem_by_name(player, "Krump and Run")
		var strat_result = strat_manager.use_stratagem(player, kar_strat_id, unit_id)
		if not strat_result.success:
			return create_result(false, [], "Failed to use %s: %s" % [_krump_and_run_strat_name, strat_result.get("error", "unknown")])

	log_phase_message("Player %d uses %s — %s can make a 6\" Normal move!" % [player, _krump_and_run_strat_name.to_upper(), unit_name])
	DebugLogger.info(str("MovementPhase: OA-8 %s activated — %s (Player %d) gets 6\" Normal move" % [_krump_and_run_strat_name, unit_name, player]))

	# Set up the reactive Normal move with 6" cap
	_krump_and_run_unit_id = unit_id
	_reactive_move_owner = player  # Override engagement checks for this player's unit

	var move_cap = 6.0
	var pivot_value = get_pivot_value_for_unit(unit_id)
	active_moves[unit_id] = {
		"mode": "NORMAL",
		"mode_locked": true,
		"completed": false,
		"move_cap_inches": move_cap,
		"advance_roll": 0,
		"model_moves": [],
		"staged_moves": [],
		"original_positions": {},
		"original_rotations": {},
		"model_distances": {},
		"dice_rolls": [],
		"battle_shocked": false,
		"pivot_value": pivot_value,
		"pivot_cost_applied": false,
		"group_moves": [],
		"group_selection": [],
		"group_formation": {},
		"is_reactive_move": true,  # Flag to identify reactive moves
		"reactive_source": "krump_and_run"
	}

	# Store original positions for potential reset (composite keys for consistency)
	for model in unit.get("models", []):
		if model.get("alive", true):
			var model_id = model.get("id", "")
			var model_key = "%s:%s" % [unit_id, model_id]
			var pos = _get_model_position(model)
			active_moves[unit_id]["original_positions"][model_key] = pos
			active_moves[unit_id]["original_rotations"][model_key] = model.get("rotation", 0.0)

	emit_signal("unit_move_begun", unit_id, "NORMAL")

	# Clear awaiting state
	_awaiting_krump_and_run = false
	_krump_and_run_eligible_units = []
	_krump_and_run_fell_back_unit_id = ""

	var result = create_result(true, [])
	result["krump_and_run_used"] = true
	result["krump_and_run_unit_id"] = unit_id
	result["krump_and_run_player"] = player
	result["krump_and_run_move_cap"] = move_cap
	return result

func _process_decline_krump_and_run(action: Dictionary) -> Dictionary:
	"""Process declining the reactive fall-back stratagem (Krump and Run / On to da Next)."""
	var player = _krump_and_run_player
	log_phase_message("Player %d declined %s" % [player, _krump_and_run_strat_name.to_upper()])
	DebugLogger.info(str("MovementPhase: OA-8 %s DECLINED by Player %d" % [_krump_and_run_strat_name, player]))

	# Clear state
	_awaiting_krump_and_run = false
	_krump_and_run_player = 0
	_krump_and_run_eligible_units = []
	_krump_and_run_fell_back_unit_id = ""
	_krump_and_run_unit_id = ""
	_krump_and_run_strat_id = ""

	return _ork11e_with_enemy_ended_move(create_result(true, []))

# ============================================================================
# OA-42: SCATTER! — GROT TANKS REACTIVE MOVE
# ============================================================================
# "Once per turn, when an enemy unit ends a Normal, Advance or Fall Back move
# within 9" of this unit, if this unit is not within Engagement Range of one
# or more enemy units, it can make a Normal move of up to 6"."

func _check_scatter_opportunity(trigger_unit_id: String, snapshot_override: Dictionary = {}) -> Dictionary:
	"""Check if any defending unit with Scatter! can react after an enemy ends a move within 9\".
	Returns { triggered: bool, result_extra: Dictionary }."""
	var trigger_unit = get_unit(trigger_unit_id)
	var active_player = get_current_player()  # The player who just moved
	var defending_player = 2 if active_player == 1 else 1  # Potential Scatter! player

	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if not ability_mgr:
		return {"triggered": false}

	var check_snapshot = snapshot_override if not snapshot_override.is_empty() else game_state_snapshot

	# Get the trigger unit's position from the snapshot (post-move)
	var trigger_unit_data = check_snapshot.get("units", {}).get(trigger_unit_id, {})
	var trigger_pos = _get_unit_center(trigger_unit_data)
	if trigger_pos == null:
		return {"triggered": false}

	# MORE GITZ OVER 'ERE! (Kult of Speed) / CONNIVING RUNTS (Dread Mob):
	# stratagem-granted reactions in the same window (enemy ends a
	# Normal/Advance/Fall Back move within 9"). Detachments are exclusive per
	# player, so at most one candidate resolves.
	var mg_strat_id = ""
	var mg_strat_name = ""
	var strat_manager_sc = get_node_or_null("/root/StratagemManager")
	if strat_manager_sc:
		for sc_candidate in ["More Gitz Over 'Ere!", "Conniving Runts"]:
			var sc_id = strat_manager_sc.find_faction_stratagem_by_name(defending_player, sc_candidate)
			if sc_id != "" and strat_manager_sc.can_use_stratagem(defending_player, sc_id).can_use:
				mg_strat_id = sc_id
				mg_strat_name = sc_candidate
				break

	# Find eligible units with Scatter! ability (or the MORE GITZ stratagem)
	var eligible = []
	var units = check_snapshot.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		if int(unit.get("owner", 0)) != defending_player:
			continue
		if _is_unit_destroyed_check(unit):
			continue
		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
			continue

		# Route A: the Scatter! ability (free, once per turn per unit).
		var via_ability: bool = ability_mgr.has_scatter(unit_id) and not ability_mgr.is_scatter_used_this_turn(unit_id)
		# Route B: MORE GITZ OVER 'ERE! (1 CP, per-target conditions enforced
		# by can_use_stratagem — SPEED FREEKS keyword, unengaged).
		var via_stratagem: bool = false
		if not via_ability and mg_strat_id != "":
			via_stratagem = strat_manager_sc.can_use_stratagem(defending_player, mg_strat_id, unit_id).can_use
		if not (via_ability or via_stratagem):
			continue

		# Must NOT be in engagement range of any enemy unit
		if _is_unit_engaged_for_player(unit_id, defending_player, check_snapshot):
			continue

		# Must not be battle-shocked
		if unit.get("flags", {}).get("battle_shocked", false) or unit.get("status_effects", {}).get("battle_shocked", false):
			continue

		# Check if the trigger unit ended within 9" of this unit
		var unit_pos = _get_unit_center(unit)
		if unit_pos == null:
			continue

		var dist_inches = Measurement.px_to_inches(unit_pos.distance_to(trigger_pos))
		if dist_inches > 9.0:
			continue

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		eligible.append({"unit_id": unit_id, "unit_name": unit_name, "via_stratagem": via_stratagem,
			"strat_id": mg_strat_id if via_stratagem else "", "strat_name": mg_strat_name if via_stratagem else ""})
		DebugLogger.info(str("MovementPhase: OA-42 %s — %s is eligible (%.1f\" from trigger unit)" % [
			mg_strat_name.to_upper() if via_stratagem else "Scatter!", unit_name, dist_inches]))

	if eligible.is_empty():
		return {"triggered": false}

	# Scatter! is available!
	_awaiting_scatter = true
	_scatter_player = defending_player
	_scatter_eligible_units = eligible
	_scatter_trigger_unit_id = trigger_unit_id

	var trigger_name = trigger_unit.get("meta", {}).get("name", trigger_unit_id)
	log_phase_message("SCATTER! available for Player %d (%d eligible units) after %s moved within 9\"" % [defending_player, eligible.size(), trigger_name])
	DebugLogger.info(str("MovementPhase: OA-42 Scatter! opportunity — Player %d has %d eligible units" % [defending_player, eligible.size()]))

	emit_signal("scatter_opportunity", defending_player, eligible, trigger_unit_id)

	return {
		"triggered": true,
		"result_extra": {
			"trigger_scatter": true,
			"awaiting_scatter": true,
			"scatter_player": defending_player,
			"scatter_eligible_units": eligible,
			"scatter_trigger_unit_id": trigger_unit_id,
		}
	}

func _validate_use_scatter(action: Dictionary) -> Dictionary:
	"""Validate using Scatter! ability."""
	var errors = []

	if not _awaiting_scatter:
		errors.append("Not awaiting Scatter! decision")
		return {"valid": false, "errors": errors}

	var unit_id = action.get("payload", {}).get("unit_id", "")
	if unit_id.is_empty():
		errors.append("No unit specified for Scatter!")
		return {"valid": false, "errors": errors}

	# Validate the unit is in the eligible list
	var found = false
	for eligible in _scatter_eligible_units:
		if eligible.unit_id == unit_id:
			found = true
			break
	if not found:
		errors.append("Unit %s is not eligible for Scatter!" % unit_id)
		return {"valid": false, "errors": errors}

	return {"valid": true, "errors": []}

func _process_use_scatter(action: Dictionary) -> Dictionary:
	"""Process using Scatter! — set up reactive Normal move of up to 6\".
	Also serves MORE GITZ OVER 'ERE! (Kult of Speed): eligible entries carry
	via_stratagem=true and the stratagem is used (CP spent) instead of
	marking the Scatter! ability as used."""
	var unit_id = action.get("payload", {}).get("unit_id", "")
	var player = _scatter_player
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)

	var used_strat_name = ""
	for entry in _scatter_eligible_units:
		if entry.get("unit_id", "") == unit_id and entry.get("via_stratagem", false):
			var strat_manager_us = get_node_or_null("/root/StratagemManager")
			if strat_manager_us:
				var mg_result = strat_manager_us.use_stratagem(player, entry.get("strat_id", ""), unit_id)
				if not mg_result.get("success", false):
					return create_result(false, [], "%s could not be used: %s" % [entry.get("strat_name", "Reactive stratagem"), str(mg_result.get("error", "unknown"))])
				used_strat_name = entry.get("strat_name", "More Gitz Over 'Ere!")
			break

	if used_strat_name == "":
		# Mark Scatter! as used this turn for this unit
		var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
		if ability_mgr:
			ability_mgr.mark_scatter_used_this_turn(unit_id)

	# CONNIVING RUNTS (Dread Mob): before the move, roll one D6 — on a 4+ the
	# enemy unit that just moved suffers D3+1 mortal wounds.
	var is_conniving_runts: bool = used_strat_name.to_upper().replace("’", "'") == "CONNIVING RUNTS"
	if is_conniving_runts and _scatter_trigger_unit_id != "":
		var cr = RulesEngine.resolve_conniving_runts(_scatter_trigger_unit_id, GameState.create_snapshot(), RulesEngine.make_rng())
		if not cr.get("diffs", []).is_empty():
			PhaseManager.apply_state_changes(cr.get("diffs", []))
		var trig_name = get_unit(_scatter_trigger_unit_id).get("meta", {}).get("name", _scatter_trigger_unit_id)
		log_phase_message("CONNIVING RUNTS: rolled %d — %d mortal wound(s) to %s" % [
			int(cr.get("roll", 0)), int(cr.get("mortal_wounds", 0)), trig_name])

	# Scatter!/MORE GITZ move up to 6"; CONNIVING RUNTS grants a full Normal move.
	var move_cap = 6.0
	if is_conniving_runts:
		move_cap = float(unit.get("meta", {}).get("stats", {}).get("move", 6))

	log_phase_message("Player %d uses %s — %s can make a %.0f\" Normal move!" % [player, used_strat_name.to_upper() if used_strat_name != "" else "SCATTER!", unit_name, move_cap])
	DebugLogger.info(str("MovementPhase: OA-42 %s activated — %s (Player %d) gets %.0f\" Normal move" % [used_strat_name if used_strat_name != "" else "Scatter!", unit_name, player, move_cap]))

	# Set up the reactive Normal move
	_scatter_unit_id = unit_id
	_reactive_move_owner = player  # Override engagement checks for this player's unit

	var pivot_value = get_pivot_value_for_unit(unit_id)
	active_moves[unit_id] = {
		"mode": "NORMAL",
		"mode_locked": true,
		"completed": false,
		"move_cap_inches": move_cap,
		"advance_roll": 0,
		"model_moves": [],
		"staged_moves": [],
		"original_positions": {},
		"original_rotations": {},
		"model_distances": {},
		"dice_rolls": [],
		"battle_shocked": false,
		"pivot_value": pivot_value,
		"pivot_cost_applied": false,
		"group_moves": [],
		"group_selection": [],
		"group_formation": {},
		"is_reactive_move": true,
		"reactive_source": "scatter"
	}

	# Store original positions for potential reset (composite keys for consistency)
	for model in unit.get("models", []):
		if model.get("alive", true):
			var model_id = model.get("id", "")
			var model_key = "%s:%s" % [unit_id, model_id]
			var pos = _get_model_position(model)
			active_moves[unit_id]["original_positions"][model_key] = pos
			active_moves[unit_id]["original_rotations"][model_key] = model.get("rotation", 0.0)

	emit_signal("unit_move_begun", unit_id, "NORMAL")

	# Clear awaiting state
	_awaiting_scatter = false
	_scatter_eligible_units = []
	_scatter_trigger_unit_id = ""

	var result = create_result(true, [])
	result["scatter_used"] = true
	result["scatter_unit_id"] = unit_id
	result["scatter_player"] = player
	result["scatter_move_cap"] = move_cap
	return result

func _process_decline_scatter(action: Dictionary) -> Dictionary:
	"""Process declining the Scatter! ability."""
	var player = _scatter_player
	log_phase_message("Player %d declined SCATTER!" % player)
	DebugLogger.info(str("MovementPhase: OA-42 Scatter! DECLINED by Player %d" % player))

	# Clear state
	_awaiting_scatter = false
	_scatter_player = 0
	_scatter_eligible_units = []
	_scatter_trigger_unit_id = ""
	_scatter_unit_id = ""

	return _ork11e_with_enemy_ended_move(create_result(true, []))

# ============================================================================
# CODEX: ORKS (11e) — STRATAGEM WINDOWS + FOLLOW-UPS
# (design .llm/ork_codex_11e_design.md §3, §3.2, §6; handlers in
# scripts/stratagems/ork_codex/OrkCodexMovement.gd)
# ============================================================================
#   unit_selected_to_move       BEGIN_NORMAL_MOVE / BEGIN_ADVANCE / BEGIN_FALL_BACK,
#                               before any roll or move cap (active player)
#   enemy_selected_to_fall_back BEGIN_FALL_BACK, queued after the above (opponent)
#   unit_ended_normal_move      CONFIRM_UNIT_MOVE of a normal move (active player)
#   enemy_ended_move            CONFIRM_UNIT_MOVE of the active player's unit, after
#                               the overwatch / Krump and Run / Scatter! prompts (opponent)
#   movement_phase_start / _end phase entry / END_MOVEMENT (active player first)
# Follow-ups: reactive_normal_move (human: drag + End This Unit's Move; AI:
# auto-move) and assault_disembark (human: disembark dialog + placement; AI:
# auto-placement).

func _ork11e_move_type(mode: String) -> String:
	match mode:
		"NORMAL":
			return "normal"
		"ADVANCE":
			return "advance"
		"FALL_BACK":
			return "fall_back"
		"SURGE":
			return "surge"
	return mode.to_lower()

## Append window diffs (CP + effects of synchronous/AI uses) to a result.
func _ork11e_merge_diffs(result: Dictionary, diffs: Array) -> Dictionary:
	if diffs.is_empty():
		return result
	var merged: Array = result.get("changes", []).duplicate()
	merged.append_array(diffs)
	result["changes"] = merged
	return result

## unit_selected_to_move (+ enemy_selected_to_fall_back for a fall-back move),
## before any roll or cap is computed. Each window opens once per unit and move
## type per phase: the drag UI re-sends BEGIN_NORMAL_MOVE on selection AND on
## "Confirm Movement Mode", and a player may switch Normal -> Advance (the
## Advance window then offers the advance-only stratagems). Returns {paused, diffs}.
func _ork11e_open_selected_to_move_windows(action: Dictionary, move_type: String) -> Dictionary:
	var none := {"paused": false, "diffs": []}
	if GameConstants.edition < 11:
		return none
	var unit_id := str(action.get("actor_unit_id", ""))
	if unit_id == "":
		return none
	var key := "%s:%s" % [unit_id, move_type]
	if _ork11e_stm_opened.has(key):
		return none
	_ork11e_stm_opened[key] = true
	var active := get_current_player()
	var entries: Array = [{"player": active, "window_id": "unit_selected_to_move",
		"ctx": {"phase": "movement", "unit_id": unit_id, "move_type": move_type}}]
	if move_type == "fall_back":
		entries.append({"player": 2 if active == 1 else 1, "window_id": "enemy_selected_to_fall_back",
			"ctx": {"phase": "movement", "enemy_unit_id": unit_id}})
	var resume_ctx := {"phase": "movement", "unit_id": unit_id, "move_type": move_type, "action": action.duplicate(true)}
	if open_stratagem_windows(entries, "_resume_after_selected_to_move", resume_ctx):
		log_phase_message("Waiting for Player %d's stratagem decision: %s selected to make a %s move" % [
			get_pending_stratagem_window_decider(), unit_id, move_type])
		return {"paused": true, "diffs": consume_window_diffs()}
	return {"paused": false, "diffs": consume_window_diffs()}

## Resume point for the selected-to-move windows (BasePhase framework).
func _resume_after_selected_to_move(ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	var action: Dictionary = ctx.get("action", {})
	match str(ctx.get("move_type", "")):
		"normal":
			return _process_begin_normal_move_after_windows(action)
		"advance":
			return _process_begin_advance_after_windows(action)
		"fall_back":
			return _process_begin_fall_back_after_windows(action)
		"disembark":  # Codex: Space Marines (11e) AGGRESSIVE DISEMBARKATION (SMCodex11e.gd)
			return _process_disembark_unit_after_windows(action)
	return create_result(true, [])

## Resume point for unit_ended_normal_move: the remaining post-move prompts.
func _resume_after_unit_ended_normal_move(ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	var unit_id := str(ctx.get("unit_id", ""))
	return _post_move_prompts(unit_id, active_moves.get(unit_id, {"mode": "NORMAL"}), [], [])

## Opens the opponent's enemy_ended_move window for the move recorded in
## _ork11e_eem_pending — only once no other post-move prompt (overwatch,
## Krump and Run, Scatter! and their reactive moves) is outstanding.
## continue_active_abilities: resume the moving unit's own post-move
## abilities afterwards (the inline confirm path). Returns {paused, diffs}.
func _ork11e_try_enemy_ended_move_window(continue_active_abilities: bool) -> Dictionary:
	var none := {"paused": false, "diffs": []}
	if _ork11e_eem_pending.is_empty() or GameConstants.edition < 11:
		return none
	if _awaiting_fire_overwatch or _awaiting_overwatch_decision or _awaiting_krump_and_run or _awaiting_scatter \
			or _krump_and_run_unit_id != "" or _scatter_unit_id != "" \
			or has_pending_stratagem_window() or _window_followup_pending:
		return none
	var pending := _ork11e_eem_pending
	_ork11e_eem_pending = {}
	var trigger_id := str(pending.get("unit_id", ""))
	var trigger := get_unit(trigger_id)
	if trigger.is_empty() or int(trigger.get("owner", 0)) != get_current_player():
		return none
	var defender := 2 if get_current_player() == 1 else 1
	var ctx := {"phase": "movement", "enemy_unit_id": trigger_id, "move_type": str(pending.get("move_type", "")),
		"continue_active_abilities": continue_active_abilities,
		# Codex: Adeptus Custodes RAPID REACTIONS (CustodesCodex11e.gd): "engaged with that enemy unit at the start of the phase".
		"engagement_at_phase_start": _engagement_at_phase_start.duplicate(true)}
	# Offers (SCARPER!'s 8" gate, ...) and AI follow-ups must see the moved
	# unit where it ended, even when this runs inside its CONFIRM action.
	# Staging is a no-op once BasePhase has applied the move.
	var eem_staged := _ork11e_stage_move_positions(_ork11e_pending_move_changes)
	_ork11e_pending_move_changes = []
	var eem_opened := open_stratagem_window(defender, "enemy_ended_move", ctx, "_resume_after_enemy_ended_move")
	_ork11e_restore_move_positions(eem_staged)
	if eem_opened:
		log_phase_message("Waiting for Player %d's enemy_ended_move stratagem decision (%s ended a %s move)" % [
			defender, trigger_id, str(pending.get("move_type", ""))])
		return {"paused": true, "diffs": consume_window_diffs()}
	return {"paused": false, "diffs": consume_window_diffs()}

## Windows opened inside CONFIRM_UNIT_MOVE run before BasePhase applies the
## move's `changes` to GameState, yet window offers (SCARPER!'s 8" gate, ...)
## and AI follow-ups (auto reactive move, assault disembark set-up) read
## GameState (and this phase's game_state_snapshot, which validation such as
## CONFIRM_DISEMBARK reads). Put the moved models at their new position /
## rotation in both for the window, then restore them
## (_ork11e_restore_move_positions) so the action's own diff application - and
## the reverse diffs captured for it - are unchanged.
func _ork11e_stage_move_positions(changes: Array) -> Dictionary:
	var saved := {}
	var stores: Array = [GameState.state]
	if not is_same(game_state_snapshot, GameState.state):
		stores.append(game_state_snapshot)
	for c in changes:
		if not c is Dictionary or str(c.get("op", "")) != "set":
			continue
		var parts: PackedStringArray = str(c.get("path", "")).split(".")
		if parts.size() != 5 or parts[0] != "units" or parts[2] != "models" or not parts[4] in ["position", "rotation"]:
			continue
		var idx := int(parts[3])
		for si in range(stores.size()):
			var models: Array = stores[si].get("units", {}).get(parts[1], {}).get("models", [])
			if idx < 0 or idx >= models.size():
				continue
			var key := "%d|%s|%d|%s" % [si, parts[1], idx, parts[4]]
			if not saved.has(key):
				saved[key] = {"store": stores[si], "had": models[idx].has(parts[4]), "value": models[idx].get(parts[4])}
			models[idx][parts[4]] = c.get("value")
	return saved

func _ork11e_restore_move_positions(saved: Dictionary) -> void:
	for key in saved:
		var parts: PackedStringArray = str(key).split("|")
		var models: Array = saved[key].store.get("units", {}).get(parts[1], {}).get("models", [])
		var idx := int(parts[2])
		if idx < 0 or idx >= models.size():
			continue
		if saved[key].had:
			models[idx][parts[3]] = saved[key].value
		else:
			models[idx].erase(parts[3])

## Deferred post-move prompt points (overwatch / Krump and Run / Scatter!
## resolved): open enemy_ended_move and merge its synchronous diffs.
func _ork11e_with_enemy_ended_move(result: Dictionary) -> Dictionary:
	if not result.get("success", false):
		return result
	var eem := _ork11e_try_enemy_ended_move_window(false)
	return _ork11e_merge_diffs(result, eem.diffs)

## Resume point for enemy_ended_move.
func _resume_after_enemy_ended_move(ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	if bool(ctx.get("continue_active_abilities", false)):
		var uid := str(ctx.get("enemy_unit_id", ""))
		return _post_move_active_abilities(uid, active_moves.get(uid, {"mode": ""}), [], [])
	return create_result(true, [])

## movement_phase_start (09.01): opened from _on_phase_enter. AI uses are
## applied by StratagemManager immediately (there is no action result to
## carry their diffs at phase entry).
func _ork11e_open_movement_phase_start_windows() -> void:
	if GameConstants.edition < 11:
		return
	var pm = get_node_or_null("/root/PhaseManager")
	if pm != null and pm.current_phase_instance != self:
		return  # the phase already completed (no unit could move)
	if open_stratagem_window_both_players("movement_phase_start", {"phase": "movement"}, "_resume_after_movement_phase_start"):
		log_phase_message("Waiting for Player %d's movement_phase_start stratagem decision" % get_pending_stratagem_window_decider())
	var start_diffs := consume_window_diffs()
	if not start_diffs.is_empty():
		log_phase_message("movement_phase_start: %d stratagem diff(s) applied by an AI decision at phase entry" % start_diffs.size())

func _resume_after_movement_phase_start(_ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	return create_result(true, [])

## Every path that ends the Movement phase comes here: the Codex: Orks (11e)
## movement_phase_end windows (active player, then the opponent — after Rapid
## Ingress etc., design §3), then phase_completed. 14.02.01: objective control
## is determined first, so DUBIOUS RESTRAINT sees this phase's moves.
func _complete_movement_phase(changes: Array) -> Dictionary:
	var out: Array = changes.duplicate()
	if GameConstants.edition >= 11 and not _ork11e_phase_end_windows_done:
		_ork11e_phase_end_windows_done = true
		var mm = get_node_or_null("/root/MissionManager")
		if mm != null and mm.has_method("check_all_objectives"):
			mm.check_all_objectives()
		# WP-O6 THIEVIN' SCAVENGERS (Codex: Orks 11e, Gretchin): "At the end of
		# your Movement phase, if this unit is controlling an objective, that
		# objective is secured."
		OrkAbilities11eScript.on_movement_phase_end(get_current_player())
		# WP-M2a Codex: Space Marines (11e) Vanguard Ambushers (Phobos Shock Force): hidden PHOBOS units re-roll wound rolls of 1.
		out.append_array(load("res://scripts/codex/space_marines/SMDetachmentsA.gd").on_movement_phase_end(get_current_player()))
		load("res://scripts/codex/space_marines/SMAbilitiesB.gd").on_movement_phase_end(get_current_player())  # WP-M4b RAISE THE BANNER (Codex: Space Marines 11e): controlled objective is secured
		# WP-M4c RAISE THE BANNER / BANNER OF MACRAGGE: "At the end of your Movement phase, if this unit is controlling an objective, that objective is secured."
		load("res://scripts/codex/space_marines/SMAbilitiesC.gd").on_movement_phase_end(get_current_player())
		var ctx := {"phase": "movement", "engaged_at_phase_start": _engagement_at_phase_start.keys()}
		if open_stratagem_window_both_players("movement_phase_end", ctx, "_resume_after_movement_phase_end"):
			log_phase_message("Movement phase end waits for Player %d's movement_phase_end stratagem decision" % get_pending_stratagem_window_decider())
			out.append_array(consume_window_diffs())
			var paused_res := create_result(true, out)
			paused_res.merge(consume_window_result_extra(), false)
			return paused_res
		out.append_array(consume_window_diffs())
		var extra := consume_window_result_extra()
		out.append_array(_snap_end_of_phase_cleanup())
		_recheck_objectives_after_end_rules()
		emit_signal("phase_completed")
		var sync_res := create_result(true, out)
		sync_res.merge(extra, false)
		return sync_res
	emit_signal("phase_completed")
	return create_result(true, out)

func _resume_after_movement_phase_end(_ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	log_phase_message("movement_phase_end windows answered — ending the Movement phase")
	var cleanup := _snap_end_of_phase_cleanup()
	_recheck_objectives_after_end_rules()
	emit_signal("phase_completed")
	return create_result(true, cleanup)

## 14.02: "At the end of each phase ... determine a player's level of control".
## Control was determined before the movement_phase_end windows (so DUBIOUS
## RESTRAINT sees this phase's moves); the end-of-phase rules resolved in them
## — FIRE OVERWATCH casualties, reactive moves — can change it, so it is
## determined again as the phase actually ends. (MissionManager also re-checks
## on PhaseManager.phase_completed; this keeps the phase correct on its own.)
func _recheck_objectives_after_end_rules() -> void:
	var mm = get_node_or_null("/root/MissionManager")
	if mm != null and mm.has_method("check_all_objectives"):
		mm.check_all_objectives()

## 15.09 AFTER SHOOTING lasts "until the end of the phase": lift the
## cannot_start_action lock a snap shot set this phase (applied here, and
## returned so the action's result carries it to replay / the network client).
func _snap_end_of_phase_cleanup() -> Array:
	var diffs: Array = []
	for uid in _snap_after_shooting_units:
		if not GameState.state.get("units", {}).has(uid):
			continue
		diffs.append({"op": "set", "path": "units.%s.flags.cannot_start_action" % uid, "value": false})
	_snap_after_shooting_units = []
	if not diffs.is_empty():
		PhaseManager.apply_state_changes(diffs)
		log_phase_message("[11e 15.09] end of phase — snap shooters may start actions again (%d unit(s))" % diffs.size())
	return diffs

## True while the end-of-Movement RAPID INGRESS prompt waits for its player
## (15.07: the decision, then the 20.04 ingress set-up). Both are answerable
## on the deciding peer online — NetworkManager re-emits the prompt there and
## Main starts the set-up from the mirrored USE_RAPID_INGRESS result — so at
## 11e GameManager._end_phase_via_phase (the host's END_MOVEMENT online) must
## not force-complete the phase: it used to, which skipped the prompt AND the
## movement_phase_end window behind it (FIRE OVERWATCH 15.08).
## (Main's version excluded the pre-codex SAWBONEZ / MEKANIAK / GROT OILER
## prompts here; those 10e end-of-movement prompts are gone — WP-O6.)
func has_pending_end_of_phase_prompt() -> bool:
	return _awaiting_rapid_ingress or _rapid_ingress_unit_id != ""

## A HUMAN-driven follow-up (reactive move / assault disembark) holds the
## phase like a pending window: report its owner so AIPlayer idles until it
## completes. (BasePhase's own gate only knows _window_pending.)
func get_pending_stratagem_window_decider() -> int:
	var decider := super()
	if decider > 0:
		return decider
	if not _ork11e_reactive_move.is_empty():
		return int(_ork11e_reactive_move.get("player", 0))
	if not _ork11e_assault_disembark.is_empty():
		return int(_ork11e_assault_disembark.get("player", 0))
	if not _snap_saves.is_empty():
		return int(_snap_saves.get("defender", 0))
	return 0

## Movement actions a reactive normal move (codex follow-up, Krump and Run,
## Scatter!) is made with.
const _REACTIVE_MOVE_ACTIONS := ["SET_MODEL_DEST", "STAGE_MODEL_MOVE", "UNDO_LAST_MODEL_MOVE", "RESET_UNIT_MOVE",
	"CONFIRM_UNIT_MOVE", "APPLY_PIVOT_COST", "SET_TAKE_TO_SKIES", "LOCK_MOVEMENT_MODE"]

## Network turn layer (F3 / AI-04): the follow-up owner (BasePhase), and the
## owner of a pre-existing reactive move (Krump and Run / Scatter!) moving
## THAT unit, may act during the opponent's turn.
func allows_cross_turn_action(action: Dictionary) -> bool:
	if super(action):
		return true
	var claimed := int(action.get("player", -1))
	# 11e 15.07 RAPID INGRESS: the NON-active player answers the end-of-Movement
	# prompt and sets up the arriving unit (USE / DECLINE / placement) — only
	# while this phase is waiting on THAT player's Rapid Ingress.
	if claimed > 0 and claimed == _rapid_ingress_player and (_awaiting_rapid_ingress or _rapid_ingress_unit_id != "") \
			and str(action.get("type", "")) in ["USE_RAPID_INGRESS", "DECLINE_RAPID_INGRESS", "PLACE_RAPID_INGRESS_REINFORCEMENT"]:
		return true
	var uid := str(action.get("actor_unit_id", ""))
	var move_data: Dictionary = active_moves.get(uid, {})
	return claimed > 0 and _reactive_move_owner == claimed and str(action.get("type", "")) in _REACTIVE_MOVE_ACTIONS \
		and bool(move_data.get("is_reactive_move", false)) and not bool(move_data.get("completed", false)) \
		and int(get_unit(uid).get("owner", 0)) == claimed

## While a human follow-up owns the phase only its own actions are accepted —
## and only from the player who owns it (AI-05: the opponent, e.g. an AI that
## sees the unit in active_moves, must not stage or end the owner's move).
func _ork11e_followup_gate(action: Dictionary) -> Dictionary:
	var t := str(action.get("type", ""))
	if t.begins_with("DEBUG_"):
		return {}
	if not _ork11e_reactive_move.is_empty():
		var rm_uid := str(_ork11e_reactive_move.get("unit_id", ""))
		var rm_owner := int(_ork11e_reactive_move.get("player", 0))
		if t in _REACTIVE_MOVE_ACTIONS and str(action.get("actor_unit_id", "")) == rm_uid:
			if action.has("player") and int(action.get("player", 0)) != rm_owner:
				return {"valid": false, "errors": ["Player %d is making this %s move, not Player %d" % [
					rm_owner, str(_ork11e_reactive_move.get("source", "reactive")), int(action.get("player", 0))]]}
			return {}
		var rm_msg := "Finish %s's %s move first" % [get_unit(rm_uid).get("meta", {}).get("name", rm_uid), str(_ork11e_reactive_move.get("source", "reactive"))]
		return {"valid": false, "errors": [rm_msg]}
	if not _ork11e_assault_disembark.is_empty():
		var remaining: Array = _ork11e_assault_disembark.get("remaining", [])
		var ad_uid := str(action.get("actor_unit_id", action.get("payload", {}).get("unit_id", "")))
		if ad_uid == "":
			ad_uid = str(action.get("payload", {}).get("unit_id", ""))
		if t in ["DISEMBARK_UNIT", "CONFIRM_DISEMBARK", "SKIP_ASSAULT_DISEMBARK"] and ad_uid in remaining:
			var ad_owner := int(_ork11e_assault_disembark.get("player", 0))
			if action.has("player") and int(action.get("player", 0)) != ad_owner:
				return {"valid": false, "errors": ["Player %d makes this READIED BRAWLERS assault disembark, not Player %d" % [
					ad_owner, int(action.get("player", 0))]]}
			return {}
		var ad_msg := "Finish READIED BRAWLERS first: assault disembark (or stay embarked) with %s" % ", ".join(PackedStringArray(remaining))
		return {"valid": false, "errors": [ad_msg]}
	return {}

## Follow-up executor (design §3.2).
func _execute_window_followup(player: int, window_id: String, followup: Dictionary, ctx: Dictionary) -> bool:
	match str(followup.get("type", "")):
		"reactive_normal_move":
			return _ork11e_begin_reactive_normal_move(player, followup)
		"assault_disembark":
			return _ork11e_begin_assault_disembark(player, followup)
		# Codex: Adeptus Custodes (CustodesCodex11e.gd) — resolved at once.
		"cus11e_reactive_charge":
			_cus11e_followup_reactive_charge(player, followup)
			return false
		"cus11e_shoot":
			_cus11e_followup_shoot(player, followup)
			return false
		"snap_shooting":
			return _resolve_snap_shooting_followup(player, followup)
	return super(player, window_id, followup, ctx)

## NO ESCAPE: "Declare a charge with your unit" against units that fell back
## this phase — auto-resolved (CustodesCodexMovement.resolve_reactive_charge).
## Its diffs are applied and merged into the window answer (_window_sync_diffs).
func _cus11e_followup_reactive_charge(player: int, followup: Dictionary) -> void:
	var res: Dictionary = _cus11e_codex().resolve_reactive_charge(player, followup)
	var unit_id := str(followup.get("unit_id", ""))
	var msg := str(res.get("message", ""))
	log_phase_message(msg)
	GameEventLog.add_player_entry(player, msg)
	var rolls: Array = res.get("rolls", [])
	if rolls.size() == 2:
		var dice := {"context": "charge_roll", "unit_id": unit_id, "rolls": rolls, "total": int(res.get("roll", 0)),
			"targets": [str(res.get("target_id", ""))], "charge_failed": not bool(res.get("success", false)), "source": "NO ESCAPE"}
		dice_log.append(dice)
		if has_signal("dice_rolled"):  # MovementPhase has no dice_rolled signal (the dice log + game log carry it)
			emit_signal("dice_rolled", dice)
	var diffs: Array = res.get("diffs", [])
	if not diffs.is_empty():
		PhaseManager.apply_state_changes(diffs)
		_window_sync_diffs.append_array(diffs)

## RAPID REACTIONS: "Your unit shoots using normal shooting, but while doing so
## your unit can only target that enemy unit" — auto-resolved like GUN-CRAZY
## SHOW-OFFS (every weapon that can target it, one profile per weapon), each
## component of an Attached unit with its own weapons.
func _cus11e_followup_shoot(player: int, followup: Dictionary) -> void:
	var unit_id := str(followup.get("unit_id", ""))
	var target_id := str(followup.get("forced_target_id", ""))
	var source := str(followup.get("source", "Stratagem"))
	var unit_name := GameState.get_unit_display_name(unit_id)
	var target_name := GameState.get_unit_display_name(target_id)
	var assignments: Array = _cus11e_codex().forced_shoot_assignments(unit_id, target_id)
	if assignments.is_empty():
		var none_msg := "%s: %s has no ranged weapon that can target %s — no attacks" % [source, unit_name, target_name]
		log_phase_message(none_msg)
		GameEventLog.add_player_entry(player, none_msg)
		return
	var by_shooter := {}
	for a in assignments:
		var sh := str(a.get("_shooter", unit_id))
		if not by_shooter.has(sh):
			by_shooter[sh] = []
		var clean: Dictionary = a.duplicate()
		clean.erase("_shooter")
		by_shooter[sh].append(clean)
	var hits := 0
	var wounds := 0
	var casualties := 0
	for shooter in by_shooter:
		var board := GameState.create_snapshot()
		var weapon_names: Array = []
		for a in by_shooter[shooter]:
			weapon_names.append(str(RulesEngine.get_weapon_profile(str(a.weapon_id), board).get("name", a.weapon_id)))
		var header := "%s: %s shoots %s (normal shooting, auto-resolved) with %s" % [source, GameState.get_unit_display_name(str(shooter)), target_name, ", ".join(weapon_names)]
		log_phase_message(header)
		GameEventLog.add_combat_header("P%d: %s" % [player, header])
		var res = RulesEngine.resolve_shoot({"type": "SHOOT", "actor_unit_id": str(shooter),
			"payload": {"assignments": by_shooter[shooter]}}, board, RulesEngine.make_rng())
		for db in res.get("dice", []):
			var c := str(db.get("context", ""))
			if c in ["to_hit", "auto_hit", "to_wound"] and not db.has("target_unit_id"):
				db["target_unit_id"] = target_id
			dice_log.append(db)
			if has_signal("dice_rolled"):
				emit_signal("dice_rolled", db)
			if c == "to_hit" or c == "auto_hit":
				hits += int(db.get("successes", 0))
			elif c == "to_wound":
				wounds += int(db.get("successes", 0))
		var diffs: Array = res.get("diffs", [])
		for d in diffs:
			var path := str(d.get("path", ""))
			if path.begins_with("units.%s." % target_id) and path.ends_with(".alive") and d.get("value", true) == false:
				casualties += 1
		if not diffs.is_empty():
			# Event attribution (framework F9): these are the RAPID REACTIONS
			# shooter's attacks (unit_destroyed / enemy_unit_has_attacked).
			_window_events_detect()
			var prev_attacker := _ev_action_attacker
			_ev_action_attacker = str(shooter)
			PhaseManager.apply_state_changes(diffs)
			_window_sync_diffs.append_array(diffs)
			_window_events_detect()
			_ev_action_attacker = prev_attacker
		# "until that enemy unit has attacked" effects end with its attacks.
		_cus11e_codex().on_unit_has_attacked(str(shooter))
		# Codex: Space Marines (11e) Space Wolves HEROIC RESOLVE (SWCodex11e.gd).
		load("res://scripts/codex/space_wolves/SWCodex11e.gd").on_unit_has_attacked(str(shooter))
		# Codex: Space Marines (11e) ARMOUR OF CONTEMPT ends "until that enemy unit has attacked" (SMCodex11e.gd).
		load("res://scripts/codex/space_marines/SMCodex11e.gd").on_unit_has_attacked(str(shooter))
	var summary := "%s: %s → %s: %d hit(s), %d wound(s), %d model(s) slain" % [source, unit_name, target_name, hits, wounds, casualties]
	log_phase_message(summary)
	GameEventLog.add_player_entry(player, summary)

## FIRE OVERWATCH (15.08) follow-up: the defender's unit shoots the enemy unit
## they picked using SNAP shooting (15.09), at the end of the opponent's
## Movement phase. The shooter and target are re-checked against the live
## board (the window offer was built from it a moment ago, and
## can_use_stratagem re-validated both before the CP was spent), the attacks
## are built per 04.01/04.02 (RulesEngine.build_snap_assignments_11e: every
## model of the Attached unit, per-weapon range + visibility), and resolved
## with the overwatch flag: BS 7 + critical hits clamped to 6 (only unmodified
## 6s hit) and no hit re-rolls (RulesEngine, 15.09). The DEFENDING player
## resolves the saves (05.03): a human defender orders the allocation groups
## and rolls in the allocation overlay (the phase pauses until their
## APPLY_SAVES — returns true); an AI defender, or one who lets the computer
## allocate, goes through the engine's 11e allocation at once (returns false).
## Diffs ride _window_sync_diffs into the result of the action that answered
## (or opened) the window.
func _resolve_snap_shooting_followup(player: int, followup: Dictionary) -> bool:
	var shooter_id := str(followup.get("shooter_unit_id", ""))
	var target_id := str(followup.get("target_unit_id", ""))
	var source := str(followup.get("source", "FIRE OVERWATCH"))
	var board: Dictionary = GameState.create_snapshot()
	var reason: String = StratagemManager.fire_overwatch_shooter_reason_11e(player, shooter_id, board)
	var target_ok := false
	for t in RulesEngine.snap_shooting_targets_11e(shooter_id, board):
		if str(t.get("unit_id", "")) == target_id:
			target_ok = true
			break
	if reason != "" or not target_ok:
		_window_error("%s: snap shooting %s -> %s refused (%s)" % [source, shooter_id, target_id,
			reason if reason != "" else "not a legal snap-shooting target (15.09)"])
		return false
	var shooter_name := GameState.get_unit_display_name(shooter_id)
	var target_name := GameState.get_unit_display_name(target_id)
	var assignments: Array = RulesEngine.build_snap_assignments_11e(shooter_id, target_id, board)
	if assignments.is_empty():
		var none_msg := "%s: %s has no weapon that can see %s and has it in range — no attacks" % [source, shooter_name, target_name]
		log_phase_message(none_msg)
		_snap_game_log(none_msg)
		return false
	var weapon_names: Array = []
	for a in assignments:
		weapon_names.append("%s x%d" % [str(RulesEngine.get_weapon_profile(str(a.weapon_id), board).get("name", a.weapon_id)), a.model_ids.size()])
	log_phase_message("[11e 15.09] %s: P%d %s snap-shoots %s with %s" % [source, player, shooter_name, target_name, ", ".join(weapon_names)])
	_snap_game_log(">>> FIRE OVERWATCH <<<")
	_snap_game_log("P%d: %s fires at %s (snap shooting — only unmodified 6s hit, no hit re-rolls)" % [player, shooter_name, target_name])
	var head_id := RulesEngine.attached_unit_target_id(shooter_id, board)
	var defender := int(GameState.get_unit(target_id).get("owner", 0))
	_snap_saves = {"player": player, "defender": defender, "shooter_id": shooter_id, "head_id": head_id,
		"target_id": target_id, "source": source, "shooter_name": shooter_name, "target_name": target_name,
		"components": RulesEngine.attached_unit_component_ids(shooter_id, board),
		"batches": [], "index": 0, "dice": [], "diffs": [], "hazardous_weapons": [], "log_text": ""}
	# P1-59: phase-specific rules are blocked while the out-of-phase shot resolves.
	StratagemManager.set_out_of_phase_active(true, player, shooter_id)
	var shoot_action := {"type": "SHOOT", "actor_unit_id": head_id,
		"payload": {"assignments": assignments, "overwatch": true, "shooting_type": "snap"}}
	if _snap_defender_allocates(defender):
		# 05.03 SAVE ROLLS: "The opposing player resolves the following
		# sequence" (create groups, allocation order, save rolls) — the same
		# interactive 11e allocation the Shooting phase uses. Roll the hits and
		# wounds now; the defender allocates each wound batch.
		var uw: Dictionary = RulesEngine.resolve_shoot_until_wounds(shoot_action, board, RulesEngine.make_rng())
		StratagemManager.set_out_of_phase_active(false)
		var pre_diffs: Array = uw.get("one_shot_diffs", []).duplicate()
		if not pre_diffs.is_empty():
			PhaseManager.apply_state_changes(pre_diffs)
			_window_sync_diffs.append_array(pre_diffs)
		_snap_saves["dice"] = uw.get("dice", []).duplicate()
		_snap_saves["diffs"] = pre_diffs
		_snap_saves["hazardous_weapons"] = uw.get("hazardous_weapons", [])
		_snap_saves["log_text"] = str(uw.get("log_text", ""))
		var batches: Array = uw.get("save_data_list", [])
		_snap_saves["batches"] = batches
		if batches.is_empty():
			log_phase_message("[11e 15.09] %s: no wounds — nothing for Player %d to allocate" % [source, defender])
			_snap_finish()
			return false
		pending_save_data = [batches[0]]
		_window_result_extra["save_data_list"] = [batches[0]]
		_window_result_extra["fire_overwatch_awaiting_saves"] = true
		log_phase_message("[11e 05.03] %s: %d wound batch(es) — Player %d allocates the wounds" % [source, batches.size(), defender])
		call_deferred("emit_signal", "saves_required", [batches[0]])
		return true
	var res: Dictionary = RulesEngine.resolve_shoot(shoot_action, board, RulesEngine.make_rng())
	StratagemManager.set_out_of_phase_active(false)
	var shot_diffs: Array = res.get("diffs", [])
	if not shot_diffs.is_empty():
		PhaseManager.apply_state_changes(shot_diffs)
	_window_sync_diffs.append_array(shot_diffs)
	_snap_saves["dice"] = res.get("dice", []).duplicate()
	_snap_saves["diffs"] = shot_diffs.duplicate()
	_snap_saves["log_text"] = str(res.get("log_text", ""))
	_snap_finish()
	return false

## One FIRE OVERWATCH Game Log line: written here (the peer that resolves the
## snap shot — the host online) and queued on the result as
## fire_overwatch_log_lines, which NetworkManager replays into the network
## client's Game Log (GameEventLog is local to each peer and is not synced).
func _snap_game_log(text: String) -> void:
	var gel = get_node_or_null("/root/GameEventLog")
	if gel:
		gel.add_overwatch_entry(text)
	var lines: Array = _window_result_extra.get("fire_overwatch_log_lines", [])
	lines.append(text)
	_window_result_extra["fire_overwatch_log_lines"] = lines

## Stands in for GameEventLog in _log_overwatch_results_to_game_log (which only
## calls add_overwatch_entry) so the snap shot's result lines go through
## _snap_game_log.
class _SnapLogRecorder extends RefCounted:
	var _sink: Callable
	func _init(sink: Callable) -> void:
		_sink = sink
	func add_overwatch_entry(text: String) -> void:
		_sink.call(text)

## Whether the defender allocates the snap shot's wounds itself (05.03) — the
## same rule as ShootingPhase._should_pause_for_human_saves: a human defender
## at 11e who has not delegated allocation to the computer (and ALWAYS a
## networked human defender, like AllocationGroupOverlay._compute_auto_mode).
## AI defenders resolve through the engine's 11e allocation (default legal
## order + CasualtyPreference) without pausing.
func _snap_defender_allocates(defender: int) -> bool:
	if GameConstants.edition < 11 or defender <= 0:
		return false
	if _is_ai_window_decider(defender):
		return false
	var nm = get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_method("is_networked") and nm.is_networked():
		return true
	var ss = get_node_or_null("/root/SettingsService")
	return ss != null and ss.has_method("get_auto_allocate_wounds") and not ss.get_auto_allocate_wounds()

## The snap shot is done (no wounds left to allocate): post-save [HAZARDOUS]
## checks, 15.09 AFTER SHOOTING, the Game Log / summary and the result extras.
## Its diffs are applied and ride _window_sync_diffs.
func _snap_finish() -> Array:
	var st: Dictionary = _snap_saves
	_snap_saves = {}
	pending_save_data = []
	var out: Array = []
	var dice: Array = st.get("dice", []).duplicate()
	# [HAZARDOUS] after the saves (the interactive path stops before them;
	# resolve_shoot already rolled it on the automatic path).
	for hw in st.get("hazardous_weapons", []):
		var haz = RulesEngine.resolve_hazardous_check(str(st.get("head_id", "")), str(hw.get("weapon_id", "")),
			int(hw.get("models_that_fired", 0)), GameState.create_snapshot(), RulesEngine.make_rng())
		if haz.get("hazardous_triggered", false):
			out.append_array(haz.get("diffs", []))
		dice.append_array(haz.get("dice", []))
	# 15.09 AFTER SHOOTING: until the end of the phase the unit is not eligible
	# to start an action (lifted by _snap_end_of_phase_cleanup).
	for gid in st.get("components", []):
		out.append_array(ShootingTypes.get_type("snap").after_shooting_effects(gid))
		if not gid in _snap_after_shooting_units:
			_snap_after_shooting_units.append(gid)
	if not out.is_empty():
		PhaseManager.apply_state_changes(out)
	_window_sync_diffs.append_array(out)
	var all_diffs: Array = st.get("diffs", []).duplicate()
	all_diffs.append_array(out)
	var res_like := {"dice": dice, "diffs": all_diffs, "log_text": str(st.get("log_text", ""))}
	var shooter_id := str(st.get("shooter_id", ""))
	var target_id := str(st.get("target_id", ""))
	# Through the recorder: every line also rides the result to the network
	# client's Game Log (_snap_game_log).
	_log_overwatch_results_to_game_log(_SnapLogRecorder.new(_snap_game_log), res_like, str(st.get("shooter_name", "")), str(st.get("target_name", "")), int(st.get("player", 0)),
		st.get("components", []))
	var summary := _snap_shooting_summary(str(st.get("source", "FIRE OVERWATCH")), str(st.get("shooter_name", "")), str(st.get("target_name", "")), res_like,
		target_id, st.get("components", []))
	log_phase_message(summary)
	for db in dice:
		dice_log.append(db)
	_window_result_extra["fire_overwatch_used"] = true
	_window_result_extra["fire_overwatch_unit_id"] = shooter_id
	_window_result_extra["fire_overwatch_target_id"] = target_id
	_window_result_extra["fire_overwatch_summary"] = summary
	_window_result_extra["dice"] = dice
	_window_result_extra["log_text"] = str(st.get("log_text", ""))
	# WP-M4a SENTINEL PROTOCOLS: a use that does not count against (or ignores) the
	# once-per-phase limit — the movement_phase_end window is offered again.
	if str(st.get("source", "FIRE OVERWATCH")) == "FIRE OVERWATCH":
		var sm_re: Dictionary = _sm11e_abilities_a().fire_overwatch_reoffer(int(st.get("player", 0)), {"phase": "movement", "engaged_at_phase_start": _engagement_at_phase_start.keys()})
		if not sm_re.is_empty():
			_window_queue.push_front(sm_re)
	emit_signal("overwatch_result", shooter_id, target_id, res_like)
	call_deferred("_ork11e_refresh_board_visuals")
	return out

func _validate_snap_apply_saves(action: Dictionary) -> Dictionary:
	var defender := int(_snap_saves.get("defender", 0))
	if action.has("player") and int(action.get("player", 0)) != defender:
		return {"valid": false, "errors": ["Player %d allocates the FIRE OVERWATCH wounds, not Player %d" % [defender, int(action.get("player", 0))]]}
	var list = action.get("payload", {}).get("save_results_list", [])
	if typeof(list) != TYPE_ARRAY or list.is_empty():
		return {"valid": false, "errors": ["Missing save_results_list"]}
	if typeof(list[0]) != TYPE_DICTIONARY or not list[0].get("is_allocation_11e", false):
		return {"valid": false, "errors": ["FIRE OVERWATCH saves use the 11e allocation-group summary (05.03)"]}
	if int(_snap_saves.get("index", 0)) >= _snap_saves.get("batches", []).size():
		return {"valid": false, "errors": ["No FIRE OVERWATCH save batch is waiting"]}
	return {"valid": true, "errors": []}

## One defender APPLY_SAVES for the snap shot: apply the allocation-group
## summary's idempotent set-diffs (the overlay already applied them on the
## defending peer), pay a save Command Re-roll, record the save dice; then hand
## over the next batch or finish the shot and resume the window queue / phase.
func _process_snap_apply_saves(action: Dictionary) -> Dictionary:
	var summary: Dictionary = action.get("payload", {}).get("save_results_list", [])[0]
	var batches: Array = _snap_saves.get("batches", [])
	var idx := int(_snap_saves.get("index", 0))
	var save_data: Dictionary = batches[idx]
	var diffs: Array = summary.get("diffs", []).duplicate()
	diffs.append_array(_snap_save_command_reroll(summary, save_data))
	if not diffs.is_empty():
		PhaseManager.apply_state_changes(diffs)
	var target_id := str(save_data.get("target_unit_id", _snap_saves.get("target_id", "")))
	if int(summary.get("casualties", 0)) > 0 and target_id != "":
		CharacterAttachmentManager.check_bodyguard_destroyed(target_id)
	var save_blocks: Array = RulesEngine.normalize_allocation_11e_dice(summary, {
		"target_unit_name": save_data.get("target_unit_name", target_id), "weapon_name": save_data.get("weapon_name", "")})
	_snap_saves["dice"].append_array(save_blocks)
	_snap_saves["diffs"].append_array(diffs)
	_snap_saves["index"] = idx + 1
	log_phase_message("[11e 05.03] FIRE OVERWATCH saves (batch %d/%d): %d saved, %d failed, %d casualt%s (order %s)" % [
		idx + 1, batches.size(), int(summary.get("saves_passed", 0)), int(summary.get("saves_failed", 0)),
		int(summary.get("casualties", 0)), "y" if int(summary.get("casualties", 0)) == 1 else "ies", str(summary.get("order_used", []))])
	if idx + 1 < batches.size():
		var next_batch: Dictionary = batches[idx + 1]
		pending_save_data = [next_batch]
		call_deferred("emit_signal", "saves_required", [next_batch])
		var cont := create_result(true, diffs)
		cont["save_data_list"] = [next_batch]
		cont["dice"] = save_blocks
		return cont
	_snap_finish()
	var done := _finish_window_followup(diffs)
	done.merge(consume_window_result_extra(), false)
	return done

## Defender-side save Command Re-roll from the overlay (15.02): deduct the CP
## and record the usage here, authoritatively — same as ShootingPhase.
func _snap_save_command_reroll(summary: Dictionary, save_data: Dictionary) -> Array:
	var cr = summary.get("command_reroll", {})
	if typeof(cr) != TYPE_DICTIONARY or not cr.get("used", false):
		return []
	var target_unit_id := str(save_data.get("target_unit_id", summary.get("target_unit_id", "")))
	var result = StratagemManager.execute_command_reroll(int(cr.get("player", 0)), target_unit_id, {
		"roll_type": "save_roll", "original_rolls": [int(cr.get("original", 0))],
		"unit_name": get_unit(target_unit_id).get("meta", {}).get("name", target_unit_id)})
	if not result.get("success", false):
		log_phase_message("⚠ FIRE OVERWATCH save Command Re-roll by player %d could not be paid (%s)" % [int(cr.get("player", 0)), str(result.get("error", ""))])
		return []
	return result.get("diffs", [])

## One line for the toast / log: hits, wounds, TARGET models destroyed — and,
## separately, the shooter's own models lost to [HAZARDOUS] (its post-save
## check can destroy a model of the firing unit; that is not a casualty the
## snap shot inflicted).
func _snap_shooting_summary(source: String, shooter_name: String, target_name: String, res: Dictionary,
		target_id: String = "", shooter_components: Array = []) -> String:
	var hits := 0
	var wounds := 0
	for db in res.get("dice", []):
		var c := str(db.get("context", ""))
		if c in ["to_hit", "overwatch_to_hit", "hit_roll", "auto_hit"]:
			hits += int(db.get("successes", 0))
		elif c in ["to_wound", "wound_roll"]:
			wounds += int(db.get("successes", 0))
	var killed := 0
	var own_lost := 0
	for d in res.get("diffs", []):
		var path := str(d.get("path", ""))
		if not (path.ends_with(".alive") and d.get("value") == false):
			continue
		var owner_uid := path.get_slice(".", 1) if path.begins_with("units.") else ""
		if owner_uid != "" and owner_uid in shooter_components:
			own_lost += 1
		elif target_id == "" or owner_uid == "" or owner_uid == target_id:
			killed += 1
	var line := "%s: %s snap-shot %s — %d hit(s), %d wound(s), %d model(s) destroyed" % [source, shooter_name, target_name, hits, wounds, killed]
	if own_lost > 0:
		line += " (Hazardous: %d of %s's own model(s) lost)" % [own_lost, shooter_name]
	return line

## active_moves entry for a reactive normal move (the Krump and Run / Scatter!
## shape) — the unit's owner, not the active player, makes it.
func _ork11e_setup_reactive_active_move(unit_id: String, max_inches: float, source: String) -> void:
	active_moves[unit_id] = {
		"mode": "NORMAL",
		"mode_locked": true,
		"completed": false,
		"took_to_skies": false,
		"shw_mobile": false,
		"move_cap_inches": max_inches,
		"advance_roll": 0,
		"model_moves": [],
		"staged_moves": [],
		"original_positions": {},
		"original_rotations": {},
		"model_distances": {},
		"dice_rolls": [],
		"battle_shocked": false,
		"pivot_value": get_pivot_value_for_unit(unit_id),
		"pivot_cost_applied": false,
		"group_moves": [],
		"group_selection": [],
		"group_formation": {},
		"is_reactive_move": true,
		"reactive_source": "ork11e",
		"ork11e_source": source,
	}
	var unit := get_unit(unit_id)
	var group: Array = [unit_id]
	for cid in unit.get("attachment_data", {}).get("attached_characters", []):
		group.append(str(cid))
	for gid in group:
		for model in get_unit(gid).get("models", []):
			if not model.get("alive", true):
				continue
			var key := "%s:%s" % [gid, str(model.get("id", ""))]
			active_moves[unit_id]["original_positions"][key] = _get_model_position(model)
			active_moves[unit_id]["original_rotations"][key] = model.get("rotation", 0.0)

## reactive_normal_move follow-up: "Your unit can make a normal move of up to
## X" (SCARPER!, WHIRLIGIG EVASION, WHILE THEIR BACKS ARE TURNED). Normal-move
## rules apply (max distance, end unengaged, no moving through enemy models,
## coherency at confirm). Human: paused until End This Unit's Move; AI: moved now.
func _ork11e_begin_reactive_normal_move(player: int, followup: Dictionary) -> bool:
	var unit_id := str(followup.get("unit_id", ""))
	var cap := float(followup.get("max_inches", 0.0))
	var source := str(followup.get("source", "reactive move"))
	var unit := get_unit(unit_id)
	if unit.is_empty() or _is_unit_destroyed_check(unit) or cap <= 0.0:
		log_phase_message("%s: no reactive move for %s (unit gone or 0\")" % [source, unit_id])
		return false
	var unit_name := str(unit.get("meta", {}).get("name", unit_id))
	var roll := int(followup.get("roll", 0))
	dice_log.append({"unit_id": unit_id, "unit_name": unit_name, "type": source,
		"roll": roll, "result": ("D6 = %d — normal move up to %d\"" % [roll, roll]) if roll > 0 else "normal move up to %.0f\"" % cap})
	if _is_ai_window_decider(player):
		var ai_diffs := _ork11e_auto_reactive_move(player, unit_id, cap, source, followup)
		_window_sync_diffs.append_array(ai_diffs)
		return false
	_ork11e_reactive_move = {"player": player, "unit_id": unit_id, "max_inches": cap, "source": source}
	_reactive_move_owner = player
	_ork11e_setup_reactive_active_move(unit_id, cap, source)
	log_phase_message("%s: Player %d's %s makes a normal move of up to %.1f\" — waiting for the move" % [source, player, unit_id, cap])
	emit_signal("unit_move_begun", unit_id, "NORMAL")
	return true

## AI reactive normal move: translate the whole (Attached) unit rigidly —
## away from the enemy that triggered it, or towards the nearest objective
## the player does not control — trying shorter distances / other headings
## until every model's destination passes the normal-move checks. Returns the
## applied diffs ([] = no legal move found; the unit stays where it is).
func _ork11e_auto_reactive_move(player: int, unit_id: String, cap: float, source: String, followup: Dictionary) -> Array:
	_reactive_move_owner = player
	_ork11e_setup_reactive_active_move(unit_id, cap, source)
	var move_data: Dictionary = active_moves[unit_id]
	var entries: Array = []
	var group_ids: Dictionary = {}
	for key in move_data.original_positions:
		var parts: PackedStringArray = str(key).split(":")
		var gid := parts[0]
		var mid := parts[parts.size() - 1]
		var model := _get_model_in_unit(gid, mid)
		var pos = move_data.original_positions[key]
		if model.is_empty() or pos == null:
			continue
		entries.append({"uid": gid, "model": model, "pos": pos})
		group_ids[gid] = true
	if entries.is_empty():
		active_moves.erase(unit_id)
		_reactive_move_owner = 0
		return []
	var centroid := Vector2.ZERO
	for e in entries:
		centroid += e.pos
	centroid /= float(entries.size())
	var target := _ork11e_auto_move_target(player, unit_id, centroid, followup)
	var dir := (target - centroid).normalized() if target != Vector2.INF and (target - centroid).length() > 1.0 else Vector2(0, -1 if player == 1 else 1)
	var max_px := Measurement.inches_to_px(maxf(0.0, cap - 0.05))
	if target != Vector2.INF and str(followup.get("goal", "")) != "away":
		max_px = minf(max_px, maxf(Measurement.inches_to_px(0.5), (target - centroid).length() - Measurement.inches_to_px(1.0)))
	var chosen := Vector2.INF
	for frac in [1.0, 0.75, 0.5, 0.25]:
		for ang in [0, 30, -30, 60, -60, 90, -90, 135, -135, 180]:
			var v: Vector2 = dir.rotated(deg_to_rad(float(ang))) * max_px * float(frac)
			if _ork11e_translation_legal(unit_id, move_data, entries, group_ids, v, cap):
				chosen = v
				break
		if chosen != Vector2.INF:
			break
	if chosen == Vector2.INF:
		log_phase_message("%s: AI found no legal normal move for %s — it stays where it is" % [source, unit_id])
		active_moves.erase(unit_id)
		_reactive_move_owner = 0
		return []
	var moved_in := Measurement.px_to_inches(chosen.length())
	for e in entries:
		var dest: Vector2 = e.pos + chosen
		move_data.staged_moves.append({"model_id": str(e.model.get("id", "")), "model_source_unit_id": e.uid,
			"from": e.pos, "dest": dest, "rotation": e.model.get("rotation", 0.0),
			"distance": moved_in, "total_distance": moved_in, "crosses_enemy": false})
		move_data.model_distances["%s:%s" % [e.uid, str(e.model.get("id", ""))]] = moved_in
	_ork11e_auto_moving = true
	var res := _process_confirm_unit_move({"type": "CONFIRM_UNIT_MOVE", "actor_unit_id": unit_id, "payload": {}})
	_ork11e_auto_moving = false
	var diffs: Array = res.get("changes", [])
	PhaseManager.apply_state_changes(diffs)
	var gel = get_node_or_null("/root/GameEventLog")
	if gel:
		gel.add_player_entry(player, "%s: %s made a normal move of %.1f\"" % [source, get_unit(unit_id).get("meta", {}).get("name", unit_id), moved_in])
	log_phase_message("%s: AI moved %s %.1f\" (cap %.1f\")" % [source, unit_id, moved_in, cap])
	call_deferred("_ork11e_refresh_board_visuals")
	return diffs

func _ork11e_auto_move_target(player: int, unit_id: String, centroid: Vector2, followup: Dictionary) -> Vector2:
	var away_id := str(followup.get("away_from_unit_id", ""))
	if str(followup.get("goal", "")) == "away" and away_id != "":
		var ec = _get_unit_center(get_unit(away_id))
		if ec != null and (centroid - ec).length() > 1.0:
			return centroid + (centroid - ec).normalized() * Measurement.inches_to_px(24.0)
	var best := Vector2.INF
	var best_d := INF
	var mm = get_node_or_null("/root/MissionManager")
	for obj in GameState.state.get("board", {}).get("objectives", []):
		if mm != null and int(mm.objective_control_state.get(str(obj.get("id", "")), 0)) == player:
			continue
		var op = obj.get("position", null)
		if op == null:
			continue
		var opv := Vector2(float(op.x), float(op.y)) if op is Vector2 else Vector2(float(op.get("x", 0)), float(op.get("y", 0)))
		if centroid.distance_to(opv) < best_d:
			best_d = centroid.distance_to(opv)
			best = opv
	if best != Vector2.INF:
		return best
	for eid in GameState.state.get("units", {}):
		var e = GameState.state.units[eid]
		if int(e.get("owner", 0)) == player or _is_unit_destroyed_check(e):
			continue
		var ec2 = _get_unit_center(e)
		if ec2 != null and centroid.distance_to(ec2) < best_d:
			best_d = centroid.distance_to(ec2)
			best = ec2
	return best

## Normal-move legality of a rigid translation `v` of every model in `entries`
## (the same checks STAGE_MODEL_MOVE runs, minus overlaps inside the moving
## unit — a rigid translation keeps its models apart and in coherency).
func _ork11e_translation_legal(unit_id: String, move_data: Dictionary, entries: Array, group_ids: Dictionary, v: Vector2, cap: float) -> bool:
	var fly := _unit_has_fly_keyword(unit_id)
	var kws := _terrain_rule_keywords(unit_id, move_data)
	for e in entries:
		var model: Dictionary = e.model
		var from: Vector2 = e.pos
		var dest: Vector2 = from + v
		var dist := Measurement.distance_inches(from, dest) + _get_movement_terrain_penalty(from, dest, unit_id, false)
		if dist > cap + MOVEMENT_CAP_EPSILON:
			return false
		if not _check_dense_terrain_gate(unit_id, move_data, from, dest, model).valid:
			return false
		if not _check_engagement_range_at_position(e.uid, str(model.get("id", "")), dest, "NORMAL").valid:
			return false
		if not fly and _path_crosses_enemy_bases(from, dest, unit_id, model):
			return false
		if not fly and _path_crosses_monster_vehicle_bases(from, dest, unit_id, model):
			return false
		if _position_intersects_terrain(dest, model):
			return false
		if _position_outside_board_bounds(dest, model):
			return false
		var at_dest: Dictionary = model.duplicate(true)
		at_dest["position"] = dest
		if Measurement.model_overlaps_any_wall(at_dest, kws):
			return false
		for oid in GameState.state.get("units", {}):
			if group_ids.has(oid):
				continue
			for om in GameState.state.units[oid].get("models", []):
				if not om.get("alive", true) or om.get("position", null) == null:
					continue
				if Measurement.models_overlap(at_dest, om) and not _is_touching_within_tolerance(at_dest, om):
					return false
	return true

func _ork11e_refresh_board_visuals() -> void:
	if not is_inside_tree():
		return
	var main = get_tree().current_scene
	if main != null and main.has_method("_recreate_unit_visuals"):
		main._recreate_unit_visuals()

## assault_disembark follow-up (READIED BRAWLERS): every unit embarked within
## the WAGON may make an assault disembark move (18.06), one at a time.
## Human: paused — MovementController shows the disembark dialog + placement
## for each unit (CONFIRM_DISEMBARK, or SKIP_ASSAULT_DISEMBARK to stay
## embarked). AI: every eligible unit is auto-placed now.
func _ork11e_begin_assault_disembark(player: int, followup: Dictionary) -> bool:
	var transport_id := str(followup.get("transport_id", ""))
	var units: Array = Ork11eMovement.assault_disembark_candidates(transport_id)
	units = _sm11e_abilities_a().filter_assault_disembark(transport_id, units)  # WP-M4a AERIAL ASSAULT: Deep Strike units only
	if units.is_empty():
		_window_sync_diffs.append_array(_ork11e_readied_brawlers_off(transport_id))
		return false
	if _is_ai_window_decider(player):
		var ai_diffs: Array = []
		for uid in units:
			var ai_payload := _ork11e_ai_assault_disembark_payload(str(uid), transport_id, player)
			if ai_payload.is_empty():
				log_phase_message("READIED BRAWLERS: AI found no assault disembark set-up for %s — it stays embarked" % uid)
				continue
			var res := _process_confirm_disembark({"type": "CONFIRM_DISEMBARK", "actor_unit_id": uid, "player": player,
				"payload": ai_payload})
			if not res.get("success", false):
				log_phase_message("READIED BRAWLERS: AI assault disembark of %s refused: %s" % [uid, str(res.get("error", ""))])
				continue
			PhaseManager.apply_state_changes(res.get("changes", []))
			ai_diffs.append_array(res.get("changes", []))
		ai_diffs.append_array(_ork11e_readied_brawlers_off(transport_id))
		_window_sync_diffs.append_array(ai_diffs)
		call_deferred("_ork11e_refresh_board_visuals")
		return false
	_ork11e_assault_disembark = {"player": player, "transport_id": transport_id, "remaining": units.duplicate()}
	log_phase_message("READIED BRAWLERS: Player %d may assault disembark %s from %s" % [player, str(units), transport_id])
	emit_signal("ork11e_assault_disembark_requested", player, transport_id, str(units[0]))
	return true

## READIED BRAWLERS (AI decider): a CONFIRM_DISEMBARK payload for `uid`'s
## assault disembark, or {} when no legal set-up exists. Tries the AI's own
## AIDecisionMaker._compute_disembark_positions first; its circular model of
## the hull misplaces models beside long rectangular WAGON hulls, so when that
## set-up fails validation (or the unit has an attached CHARACTER, which it does
## not place) a greedy shape-aware placement is used instead.
func _ork11e_ai_assault_disembark_payload(uid: String, transport_id: String, player: int) -> Dictionary:
	var group: Array = [uid]
	for c in get_unit(uid).get("attachment_data", {}).get("attached_characters", []):
		if str(get_unit(str(c)).get("embarked_in", "")) == transport_id:
			group.append(str(c))
	if group.size() == 1:
		var ADM = load("res://scripts/AIDecisionMaker.gd")
		var positions: Array = ADM._compute_disembark_positions(GameState.get_unit(uid), GameState.get_unit(transport_id),
			GameState.state.get("units", {}), player, GameState.state)
		if not positions.is_empty():
			var payload := {"positions": positions}
			var v := _validate_confirm_disembark({"type": "CONFIRM_DISEMBARK", "actor_unit_id": uid, "payload": payload})
			if v.get("valid", false):
				return payload
			log_phase_message("READIED BRAWLERS: AI default disembark set-up for %s rejected (%s) — using shape-aware placement" % [uid, str(v.get("errors", []))])
	return _ork11e_greedy_disembark_payload(uid, group, transport_id, player)

## Greedy placement on a 0.5" grid around the hull: every candidate honours the
## checks _validate_confirm_disembark makes (within 3" of the hull, no overlap,
## outside engagement range, on the board). The first model takes the legal
## spot nearest the enemy (the point of an assault disembark is to charge);
## the rest pack around the models already placed so the unit stays coherent.
func _ork11e_greedy_disembark_payload(uid: String, group: Array, transport_id: String, player: int) -> Dictionary:
	var transport := get_unit(transport_id)
	var tmodels: Array = transport.get("models", [])
	if tmodels.is_empty() or tmodels[0].get("position") == null:
		return {}
	var tp = tmodels[0].position
	var tpos := Vector2(float(tp.x), float(tp.y)) if tp is Dictionary else Vector2(tp)
	var px_in := Measurement.inches_to_px(1.0)
	var to_place: Array = []
	var max_r := 0.0
	for gid in group:
		var gm: Array = get_unit(str(gid)).get("models", [])
		for i in range(gm.size()):
			if gm[i].get("alive", true):
				to_place.append([str(gid), i, gm[i]])
				max_r = maxf(max_r, Measurement.base_extent_px(gm[i]))
	if to_place.is_empty():
		return {}
	var reach := Measurement.base_extent_px(tmodels[0]) + 3.0 * px_in + 2.0 * max_r
	# Obstacles near the hull (every other on-board model) and enemy models.
	var obstacles: Array = []
	var enemies: Array = []
	for oid in game_state_snapshot.get("units", {}):
		if oid in group:
			continue
		var ou: Dictionary = game_state_snapshot.units[oid]
		if ou.get("embarked_in", null) != null:
			continue
		for om in ou.get("models", []):
			if not om.get("alive", true) or om.get("position") == null:
				continue
			var op = om.position
			var opos := Vector2(float(op.x), float(op.y)) if op is Dictionary else Vector2(op)
			if int(ou.get("owner", 0)) != player:
				enemies.append(opos)
			if opos.distance_to(tpos) <= reach + 4.0 * px_in:
				obstacles.append(om)
	var cands: Array = []
	var step := 0.5 * px_in
	var n := int(ceil(reach / step))
	for gx in range(-n, n + 1):
		for gy in range(-n, n + 1):
			var c := tpos + Vector2(gx * step, gy * step)
			var near := INF
			for e in enemies:
				near = minf(near, c.distance_to(e))
			cands.append({"pos": c, "enemy": near})
	cands.sort_custom(func(a, b): return a.enemy < b.enemy)
	var placed: Array = []
	var out := {}
	for entry in to_place:
		var gid: String = entry[0]
		var model: Dictionary = entry[2]
		var order: Array = cands
		if not placed.is_empty():
			var centroid := Vector2.ZERO
			for pm in placed:
				centroid += Vector2(float(pm.position.x), float(pm.position.y))
			centroid /= float(placed.size())
			order = cands.duplicate()
			order.sort_custom(func(a, b): return a.pos.distance_squared_to(centroid) < b.pos.distance_squared_to(centroid))
		var chosen := {}
		for cand in order:
			var pos: Vector2 = cand.pos
			var at: Dictionary = model.duplicate()
			at["position"] = {"x": pos.x, "y": pos.y}
			if not TransportManager.is_position_within_disembark_range(pos, model, transport, 3.0).get("within_range", false):
				continue
			if _position_outside_board_bounds(pos, at):
				continue
			var clash := false
			for other in placed:
				if Measurement.models_overlap(at, other):
					clash = true
					break
			if clash:
				continue
			if not placed.is_empty():
				var coherent := false
				for other in placed:
					if Measurement.is_within_coherency(at, other):
						coherent = true
						break
				if not coherent:
					continue
			for other in obstacles:
				if Measurement.models_overlap(at, other):
					clash = true
					break
			if clash or _model_in_engagement_range(at, int(get_unit(gid).get("owner", player))):
				continue
			chosen = at
			break
		if chosen.is_empty():
			return {}
		placed.append(chosen)
		if not out.has(gid):
			out[gid] = []
		out[gid].append({"x": float(chosen.position.x), "y": float(chosen.position.y)})
	var payload := {"positions": out.get(uid, [])}
	if group.size() > 1:
		payload["group_positions"] = out
	var v := _validate_confirm_disembark({"type": "CONFIRM_DISEMBARK", "actor_unit_id": uid, "payload": payload})
	if not v.get("valid", false):
		log_phase_message("READIED BRAWLERS: AI shape-aware set-up for %s failed validation: %s" % [uid, str(v.get("errors", []))])
		return {}
	return payload

## READIED BRAWLERS lasts for this follow-up only: later disembarks from the
## WAGON this phase use the normal 18.04 modes again.
func _ork11e_readied_brawlers_off(transport_id: String) -> Array:
	var t := get_unit(transport_id)
	if not t.is_empty():
		t.get("flags", {}).erase(Ork11eMovement.FLAG_READIED_BRAWLERS)
	var off: Array = [{"op": "remove", "path": "units.%s.flags.%s" % [transport_id, Ork11eMovement.FLAG_READIED_BRAWLERS]}]
	off.append_array(_sm11e_abilities_a().assault_disembark_off_diffs(transport_id))  # WP-M4a Assault Ramp / Aerial Assault / Drop Pod: the grant is spent
	return off

## CONFIRM_DISEMBARK tail: when the READIED BRAWLERS follow-up is running,
## move on to the next embarked unit, or finish the follow-up.
func _ork11e_after_assault_disembark(unit_id: String, dis_changes: Array) -> Dictionary:
	if _ork11e_assault_disembark.is_empty() or not unit_id in _ork11e_assault_disembark.get("remaining", []):
		return create_result(true, dis_changes)
	_ork11e_assault_disembark["remaining"].erase(unit_id)
	return _ork11e_assault_disembark_next(dis_changes)

func _ork11e_assault_disembark_next(changes: Array) -> Dictionary:
	var tid := str(_ork11e_assault_disembark.get("transport_id", ""))
	var eligible: Array = Ork11eMovement.assault_disembark_candidates(tid)
	eligible = _sm11e_abilities_a().filter_assault_disembark(tid, eligible)  # WP-M4a AERIAL ASSAULT
	var still: Array = []
	for uid in _ork11e_assault_disembark.get("remaining", []):
		if uid in eligible:
			still.append(uid)
	_ork11e_assault_disembark["remaining"] = still
	if not still.is_empty():
		emit_signal("ork11e_assault_disembark_requested", int(_ork11e_assault_disembark.get("player", 0)), tid, str(still[0]))
		return create_result(true, changes)
	_ork11e_assault_disembark = {}
	var out: Array = changes.duplicate()
	out.append_array(_ork11e_readied_brawlers_off(tid))
	log_phase_message("READIED BRAWLERS: assault disembark follow-up complete for %s" % tid)
	return _finish_window_followup(out)

func _validate_skip_assault_disembark(action: Dictionary) -> Dictionary:
	if _ork11e_assault_disembark.is_empty():
		return {"valid": false, "errors": ["No READIED BRAWLERS assault disembark is pending"]}
	var uid := str(action.get("payload", {}).get("unit_id", action.get("actor_unit_id", "")))
	if not uid in _ork11e_assault_disembark.get("remaining", []):
		return {"valid": false, "errors": ["%s is not waiting to assault disembark" % uid]}
	return {"valid": true, "errors": []}

func _process_skip_assault_disembark(action: Dictionary) -> Dictionary:
	var uid := str(action.get("payload", {}).get("unit_id", action.get("actor_unit_id", "")))
	_ork11e_assault_disembark["remaining"].erase(uid)
	log_phase_message("READIED BRAWLERS: %s stays embarked" % uid)
	return _ork11e_assault_disembark_next([])

## Is `unit_id` waiting for its READIED BRAWLERS assault disembark? (UI)
func is_ork11e_assault_disembark_pending(unit_id: String) -> bool:
	return not _ork11e_assault_disembark.is_empty() and unit_id in _ork11e_assault_disembark.get("remaining", [])

## WHERE D'YA FINK YOU'RE GOING? forced a desperate escape: show the rolls.
func _ork11e_log_where_dya_fink_hazards(unit_id: String, hz: Dictionary) -> void:
	var u := get_unit(unit_id)
	var uname := str(u.get("meta", {}).get("name", unit_id))
	var text := "WHERE D'YA FINK YOU'RE GOING?: %s must make a desperate escape — hazard rolls %s" % [uname, str(hz.get("rolls", []))]
	if hz.has("extra_rolls"):
		text += " (incl. %d extra MONSTER/VEHICLE roll(s) %s%s)" % [hz.extra_rolls.size(), str(hz.extra_rolls),
			(", -1 battle-shocked" if int(hz.get("extra_modifier", 0)) < 0 else "")]
	text += " — %d failed, %d mortal wound(s)" % [int(hz.get("failures", 0)), int(hz.get("mortal_wounds", 0))]
	log_phase_message(text)
	dice_log.append({"unit_id": unit_id, "unit_name": uname, "type": "Desperate escape (WHERE D'YA FINK?)",
		"rolls": hz.get("rolls", []), "result": "%d failed — %d mortal wound(s)" % [int(hz.get("failures", 0)), int(hz.get("mortal_wounds", 0))]})
	var gel = get_node_or_null("/root/GameEventLog")
	if gel:
		gel.add_player_entry(int(u.get("owner", 0)), text)

# ============================================================================
# SURGE MOVE VALIDATION AND PROCESSING (P2-71)
# ============================================================================
# 10e Core Rules Update: "Surge" moves are out-of-phase moves triggered by abilities.
# Restrictions:
#   1. Each unit can only make one surge move per phase.
#   2. A unit cannot make a surge move while it is Battle-shocked.
#   3. A unit cannot make a surge move while it is within Engagement Range of
#      one or more enemy units.

func _validate_begin_surge_move(action: Dictionary) -> Dictionary:
	"""Validate that a unit can make a surge move per 10e Core Rules Update."""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}

	# 21.02 (audit #8): at e11 the SurgeMove template is authoritative —
	# eligibility plus a STATED max distance (payload.max_inches from the
	# triggering rule, or the unit's "Surge X\"" datasheet ability).
	if GameConstants.edition >= 11:
		var surge_tmpl = MoveTypes.get_type("surge")
		var surge_el = surge_tmpl.eligible(unit_id, GameState.state)
		if not surge_el.eligible:
			return {"valid": false, "errors": surge_el.reasons}
		var max_in := float(action.get("payload", {}).get("max_inches", RulesEngine.get_surge_move_inches(unit)))
		if max_in <= 0.0:
			return {"valid": false, "errors": ["No rule grants this unit a surge move (21.02 needs a stated distance)"]}
		return {"valid": true, "errors": []}

	return validate_surge_move(unit_id, unit)

func validate_surge_move(unit_id: String, unit: Dictionary) -> Dictionary:
	"""Core surge move validation — reusable from any phase.
	Checks the three 10e restrictions:
	  1. Once per phase per unit
	  2. Not while Battle-shocked
	  3. Not while in Engagement Range"""

	# Restriction 1: Each unit can only make one surge move per phase
	if _surge_moves_this_phase.has(unit_id):
		log_phase_message("Surge move denied for %s: already surged this phase" % unit_id)
		return {"valid": false, "errors": ["Unit has already made a surge move this phase"]}

	# Restriction 2: Cannot surge while Battle-shocked
	var flags = unit.get("flags", {})
	var status_effects = unit.get("status_effects", {})
	var is_battle_shocked = flags.get("battle_shocked", false) or status_effects.get("battle_shocked", false)
	if is_battle_shocked:
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		log_phase_message("Surge move denied for %s: unit is Battle-shocked" % unit_name)
		return {"valid": false, "errors": ["Battle-shocked units cannot make surge moves"]}

	# Restriction 3: Cannot surge while in Engagement Range of enemy units
	if _is_unit_engaged(unit_id):
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		log_phase_message("Surge move denied for %s: unit is within Engagement Range" % unit_name)
		return {"valid": false, "errors": ["Units within Engagement Range cannot make surge moves"]}

	# Check unit is deployed and has alive models
	if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
		return {"valid": false, "errors": ["Unit is not deployed"]}

	var has_alive = false
	for model in unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	if not has_alive:
		return {"valid": false, "errors": ["Unit has no alive models"]}

	return {"valid": true, "errors": []}

func _process_begin_surge_move(action: Dictionary) -> Dictionary:
	"""Process a surge move: roll D6 for distance, move up to result.
	The unit must end as close as possible to the closest enemy unit (excluding AIRCRAFT).
	Models can move into Engagement Range during a surge move."""
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var surge_distance = action.get("payload", {}).get("surge_distance", 0)

	# 21.02 (audit #8): at e11 the distance is STATED by the triggering rule
	# (payload.max_inches / "Surge X\"" ability) — no D6 — and the CLOSEST
	# enemy becomes the surge target (template BEFORE step).
	var surge_target_11e := ""
	if GameConstants.edition >= 11 and surge_distance <= 0:
		surge_distance = float(action.get("payload", {}).get("max_inches", RulesEngine.get_surge_move_inches(unit)))
		var surge_tmpl = MoveTypes.get_type("surge")
		var surge_before = surge_tmpl.before_moving(unit_id, GameState.state, null, {})
		surge_target_11e = str(surge_before.get("surge_target", ""))
		log_phase_message("[11e 21.02] Surge move: %s up to %0.0f\" toward closest enemy %s" % [unit_name, surge_distance, surge_target_11e])

	# If no distance specified, roll D6 for surge distance
	if surge_distance <= 0:
		var rng_seed = action.get("payload", {}).get("rng_seed", -1)
		if rng_seed == -1:
			if has_node("/root/NetworkManager"):
				var net_mgr = get_node("/root/NetworkManager")
				if net_mgr.is_networked() and net_mgr.is_host():
					rng_seed = net_mgr.get_next_rng_seed()

		var rng_service = RulesEngine.RNGService.new(rng_seed)
		var rolls = rng_service.roll_d6(1)
		surge_distance = rolls[0]
		log_phase_message("Surge move: %s → D6 = %d\"" % [unit_name, surge_distance])

	# Mark unit as having surged this phase (restriction 1)
	_surge_moves_this_phase[unit_id] = true

	# Set up active move with SURGE mode
	var pivot_value = get_pivot_value_for_unit(unit_id)
	active_moves[unit_id] = {
		"mode": "SURGE",
		"surge_target": surge_target_11e,
		"mode_locked": true,
		"completed": false,
		"move_cap_inches": surge_distance,
		"advance_roll": 0,
		"model_moves": [],
		"staged_moves": [],
		"original_positions": {},
		"original_rotations": {},
		"model_distances": {},
		"dice_rolls": [{"context": "surge", "rolls": [surge_distance]}],
		"pivot_value": pivot_value,
		"pivot_cost_applied": false,
		"group_moves": [],
		"group_selection": [],
		"group_formation": {}
	}

	dice_log.append({
		"unit_id": unit_id,
		"unit_name": unit_name,
		"type": "Surge Move",
		"roll": surge_distance,
		"result": "Surge cap = %d\"" % surge_distance
	})

	emit_signal("unit_move_begun", unit_id, "SURGE")
	log_phase_message("Surge move: %s → Move cap = %d\"" % [unit_name, surge_distance])

	# Log to GameEventLog
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log:
		var owner = int(unit.get("owner", 0))
		game_event_log.add_player_entry(owner,
			"%s makes a surge move: rolled [%d] — move up to %d\"" % [unit_name, surge_distance, surge_distance])

	return create_result(true, [
		{
			"op": "set",
			"path": "units.%s.flags.surge_moved" % unit_id,
			"value": true
		},
		{
			"op": "set",
			"path": "units.%s.flags.move_cap_inches" % unit_id,
			"value": surge_distance
		},
		{
			"op": "set",
			"path": "units.%s.flags.movement_active" % unit_id,
			"value": true
		}
	], "", {"dice": [{"context": "surge", "n": 1, "rolls": [surge_distance]}]})

func mark_unit_surged_this_phase(unit_id: String) -> void:
	"""Mark a unit as having made a surge move this phase.
	Called from other phases (ShootingPhase, FightPhase) when they trigger surge moves."""
	_surge_moves_this_phase[unit_id] = true
	log_phase_message("Marked unit %s as having surged this phase" % unit_id)

func has_unit_surged_this_phase(unit_id: String) -> bool:
	"""Check if a unit has already made a surge move this phase."""
	return _surge_moves_this_phase.has(unit_id)

func reset_surge_tracking() -> void:
	"""Reset surge move tracking. Called at start of each phase."""
	_surge_moves_this_phase.clear()

# P2-72: Normal move per-phase tracking helpers
func has_unit_normal_moved_this_phase(unit_id: String) -> bool:
	"""Check if a unit has already made a Normal move this phase.
	10e Core Rules: 'A unit cannot make more than one Normal move per phase.'"""
	return _normal_moves_this_phase.has(unit_id)

func mark_unit_normal_moved_this_phase(unit_id: String) -> void:
	"""Mark a unit as having made a Normal move this phase.
	Called externally when a Normal move is triggered outside MovementPhase."""
	_normal_moves_this_phase[unit_id] = true
	log_phase_message("P2-72: Marked unit %s as having made a Normal move this phase" % unit_id)

func reset_normal_move_tracking() -> void:
	"""Reset Normal move tracking. Called at start of each phase."""
	_normal_moves_this_phase.clear()

# Helper Methods

func _is_unit_engaged(unit_id: String) -> bool:
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	
	for model in models:
		if not model.get("alive", true):
			continue
		var pos = _get_model_position(model)
		if pos and _is_position_in_engagement_range(unit_id, model.get("id", ""), pos):
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

func _is_position_in_engagement_range(unit_id: String, model_id: String, pos: Vector2) -> bool:
	var model = _get_model_in_unit(unit_id, model_id)

	# Create a temporary model dict with the proposed position for shape-aware checks
	var model_at_pos = model.duplicate()
	model_at_pos["position"] = pos

	# Check against all enemy units using shape-aware distance
	# OA-8: During reactive moves (Krump and Run), use the reactive move owner
	# instead of the current active player for determining friendly/enemy units
	var check_player = _reactive_move_owner if _reactive_move_owner > 0 else get_current_player()
	var units = game_state_snapshot.get("units", {})

	for enemy_unit_id in units:
		var enemy_unit = units[enemy_unit_id]
		if enemy_unit.get("owner", 0) == check_player:
			continue  # Skip friendly units

		var enemy_models = enemy_unit.get("models", [])
		for enemy_model in enemy_models:
			if not enemy_model.get("alive", true):
				continue
			var enemy_pos = _get_model_position(enemy_model)
			if enemy_pos:
				# T3-9: Use barricade-aware engagement range (2" through barricades)
				var effective_er = _get_effective_engagement_range(pos, enemy_pos)
				if Measurement.is_in_engagement_range_shape_aware(model_at_pos, enemy_model, effective_er):
					return true

	return false

func _check_engagement_range_at_position(unit_id: String, model_id: String, dest: Vector2, mode: String) -> Dictionary:
	if mode == "FALL_BACK":
		# Fall Back allows ending outside ER even if path goes through
		if _is_position_in_engagement_range(unit_id, model_id, dest):
			return {"valid": false, "errors": ["Fall Back must end outside engagement range"]}
	elif mode == "SURGE":
		# Surge moves CAN end in Engagement Range (10e Core Rules Update)
		# Models can be moved within Engagement Range of enemy units during a surge
		pass
	else:
		# Normal and Advance cannot enter or end in ER
		if _is_position_in_engagement_range(unit_id, model_id, dest):
			return {"valid": false, "errors": ["Cannot end within engagement range"]}

	return {"valid": true, "errors": []}

func _unit_has_fly_keyword(unit_id: String) -> bool:
	# Check if the unit has the FLY keyword in its metadata
	var units = game_state_snapshot.get("units", {})
	var unit = units.get(unit_id, {})
	var keywords = unit.get("meta", {}).get("keywords", [])
	return "FLY" in keywords

## WP-O6 SHOKK-BOOSTA (Codex: Orks 11e, Big Mek): while making the boosted
## advance move "this unit can move through all types of model".
func _o6_moves_through_models(unit_id: String, move_data: Dictionary) -> bool:
	return (GameConstants.edition >= 11 and str(move_data.get("mode", "")) == "ADVANCE" \
		and OrkAbilities11eScript.shokk_boosta_active(unit_id)) \
		or load("res://scripts/codex/space_marines/SMAbilitiesC.gd").moves_through_models(unit_id)  # WP-M4c GRAPNEL LAUNCHERS (Reiver Squad): move through all types of model

## Codex: Adeptus Custodes CALISTUS ka'tah (CustodesKatah.gd): the unit's
## current normal / advance / fall-back move may cross every model's base.
func _cus11e_moves_through_all_models(unit_id: String) -> bool:
	var mode := str(active_moves.get(unit_id, {}).get("mode", ""))
	return _cus11e_katah().moves_through_all_models(get_unit(unit_id), mode)


## Keywords used for the 13.06 solid-terrain checks (path gate + endpoint
## wall overlap): the unit's own keywords plus per-move grants —
##   ▪ MOBILE from the 24.35 SUPER-HEAVY WALKER gamble (shw_mobile),
##   ▪ MOBILE from the Codex: Orks (11e) STOMPING JUGGERNAUT stratagem, and
##   ▪ SUPER-HEAVY WALKER (its 4" step-over) for a unit that has the 24.35
##     core ABILITY rather than the keyword — every codex datasheet that
##     prints it (Codex: Orks 11e Stompa / Gorkanaut / Morkanaut, which lost
##     their 10e Stompin' / Clankin' Forward to it). UnitAbilities.is_super_heavy_walker.
func _terrain_rule_keywords(unit_id: String, move_data: Dictionary) -> Array:
	var kws: Array = get_unit(unit_id).get("meta", {}).get("keywords", []).duplicate()
	if move_data.get("shw_mobile", false):
		kws.append("MOBILE")
	# Codex: Orks (11e) STOMPING JUGGERNAUT: "Your unit has MOBILE" (this phase).
	if get_unit(unit_id).get("flags", {}).get(Ork11eMovement.FLAG_MOBILE, false) and not "MOBILE" in kws:
		kws.append("MOBILE")
	if not "SUPER-HEAVY WALKER" in kws and UnitAbilities.is_super_heavy_walker(get_unit(unit_id)):
		kws.append("SUPER-HEAVY WALKER")
	return kws

## 24.35 SUPER-HEAVY WALKER: "Each time a unit with this ability makes a
## normal, advance or fall-back move: models in that unit can move through
## models (including MONSTER/VEHICLE models, but excluding TITANIC models)".
## Read by the enemy-base and MONSTER/VEHICLE crossing checks, which then
## only count TITANIC models as blockers. 11e only (24.35 is an 11e rule).
func _shw_moves_through_models(unit_id: String) -> bool:
	if GameConstants.edition < 11:
		return false
	var mode := str(active_moves.get(unit_id, {}).get("mode", ""))
	if not mode in ["NORMAL", "ADVANCE", "FALL_BACK"]:
		return false
	return UnitAbilities.is_super_heavy_walker(get_unit(unit_id))

static func _unit_is_titanic(unit: Dictionary) -> bool:
	for kw in unit.get("meta", {}).get("keywords", []):
		if str(kw).to_upper() == "TITANIC":
			return true
	return false

## ISS-054 (11e 13.06) path gate shared by SET_MODEL_DEST and
## STAGE_MODEL_MOVE validation: refuses a segment whose swept base crosses
## a solid dense feature the unit cannot traverse. Bypasses:
##   ▪ take-to-the-skies movers pass over models and terrain (21.03);
##   ▪ Kustom Shokk Box (Speedwaaagh!): the bearer moves horizontally
##     through terrain features when it uses its turbo (i.e. Advances).
## Returns {valid, errors} like the validators it serves.
func _check_dense_terrain_gate(unit_id: String, move_data: Dictionary, from_pos: Vector2, dest_vec: Vector2, model: Dictionary) -> Dictionary:
	if GameConstants.edition < 11:
		return {"valid": true, "errors": []}
	var flying_54: bool = move_data.get("took_to_skies", false)
	var ksb_54: bool = str(move_data.get("mode", "")) == "ADVANCE" and _unit_has_kustom_shokk_box(unit_id)
	var tm_54 = get_node_or_null("/root/TerrainManager")
	if flying_54 or tm_54 == null or not tm_54.has_method("can_move_through_11e"):
		return {"valid": true, "errors": []}
	if ksb_54:
		log_phase_message("  Kustom Shokk Box — turbo through dense terrain (13.06 bypass)")
		return {"valid": true, "errors": []}
	var kw_54 = _terrain_rule_keywords(unit_id, move_data)
	var trav = tm_54.can_move_through_11e(kw_54, from_pos, dest_vec, [], model)
	if not trav.allowed:
		# "(13.06)" alone reads like a distance in inches — spell out that it
		# is a rules reference, and tell FLY units how to get across.
		var blocker_names := ", ".join(PackedStringArray(trav.blockers))
		var msg := "Dense terrain blocks this model's path (rule 13.06): %s" % blocker_names
		if "FLY" in get_unit(unit_id).get("meta", {}).get("keywords", []):
			msg += " — tick 'Take to the skies' to fly over it"
		return {"valid": false, "errors": [msg]}
	return {"valid": true, "errors": []}

## ISS-061 (11e 21.03/24.17) — mid-move "take to the skies" toggle.
## The drag flow auto-begins a NORMAL move the moment a unit is selected —
## BEFORE the player can even see the take-to-the-skies checkbox — so the
## BEGIN_* payload alone can never carry a tick made after selection. This
## action lets the declaration be changed while the move is in progress:
## it flips move_data.took_to_skies (read by the 13.06 dense gate and the
## model-crossing checks) and re-derives the move cap (-2", 0 with HOVER).
func _validate_set_take_to_skies(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	if GameConstants.edition < 11:
		return {"valid": false, "errors": ["Take to the skies requires edition 11"]}
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}
	if not "FLY" in unit.get("meta", {}).get("keywords", []):
		return {"valid": false, "errors": ["%s does not have the FLY keyword" % unit.get("meta", {}).get("name", unit_id)]}
	# WP-O6 MADCAP ARTILLERY (Codex: Orks 11e, Traktor Kannon): "grounded" —
	# "While a unit is grounded, it cannot take to the skies."
	if bool(action.get("payload", {}).get("take_to_skies", false)) and OrkAbilities11eScript.cannot_take_to_skies(unit_id):
		return {"valid": false, "errors": ["%s is grounded (Madcap Artillery) and cannot take to the skies" % unit.get("meta", {}).get("name", unit_id)]}
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["No active move for unit"]}
	var move_data = active_moves[unit_id]
	if move_data.get("completed", false):
		return {"valid": false, "errors": ["Unit has already completed its move"]}
	if not str(move_data.get("mode", "")) in ["NORMAL", "ADVANCE", "FALL_BACK"]:
		return {"valid": false, "errors": ["Take to the skies only applies to Normal, Advance and Fall Back moves"]}
	var enabled: bool = bool(action.get("payload", {}).get("take_to_skies", false))
	if enabled == bool(move_data.get("took_to_skies", false)):
		return {"valid": true, "errors": []}  # no-op, nothing to check
	if enabled:
		# The cap shrinks (-2" unless HOVER): every model already moved must
		# still fit under the reduced cap, else the player has to reset first.
		var new_cap := _take_to_skies_recomputed_cap(unit_id, move_data, true)
		for model_key in move_data.get("model_distances", {}):
			var used: float = move_data.model_distances[model_key]
			if used > new_cap + MOVEMENT_CAP_EPSILON:
				return {"valid": false, "errors": ["Cannot take to the skies: a model has already moved %.1f\", over the reduced %.1f\" cap — Reset Unit first" % [used, new_cap]]}
	else:
		# Turning flying OFF mid-move: already-staged paths may only be legal
		# while airborne (crossed walls/models), so require a clean slate.
		if not move_data.get("staged_moves", []).is_empty() or not move_data.get("model_moves", []).is_empty():
			return {"valid": false, "errors": ["Reset the unit's move before switching off Take to the skies"]}
	return {"valid": true, "errors": []}

func _process_set_take_to_skies(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var enabled: bool = bool(action.get("payload", {}).get("take_to_skies", false))
	var move_data = active_moves[unit_id]
	if enabled == bool(move_data.get("took_to_skies", false)):
		return create_result(true, [])
	var unit = get_unit(unit_id)
	var new_cap := _take_to_skies_recomputed_cap(unit_id, move_data, enabled)
	move_data["took_to_skies"] = enabled
	move_data["move_cap_inches"] = new_cap
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	if enabled:
		log_phase_message("[11e] %s takes to the skies (mid-move toggle): cap %.1f\" (%+.1f\"), may move through models and terrain" % [unit_name, new_cap, MoveType.take_to_skies_modifier(unit)])
	else:
		log_phase_message("[11e] %s will not take to the skies: cap back to %.1f\"" % [unit_name, new_cap])
	var gel = get_node_or_null("/root/GameEventLog")
	if gel:
		if enabled:
			gel.add_player_entry(int(unit.get("owner", 0)), "%s takes to the skies (21.03): -2\" move, flies over models and terrain" % unit_name)
		else:
			gel.add_player_entry(int(unit.get("owner", 0)), "%s stays on the ground: normal terrain rules apply" % unit_name)
	return create_result(true, [{
		"op": "set",
		"path": "units.%s.flags.move_cap_inches" % unit_id,
		"value": new_cap
	}])

## Re-derive a move's cap for the given flying declaration, mirroring how
## the BEGIN_* processors built it: base M (flat 24" when turbo-boosting),
## -2" (0 with HOVER) applied to M when flying, advance roll added on top.
func _take_to_skies_recomputed_cap(unit_id: String, move_data: Dictionary, flying: bool) -> float:
	var unit = get_unit(unit_id)
	var m := float(get_unit_movement(unit))
	if flying:
		m = max(0.0, m + MoveType.take_to_skies_modifier(unit))
	if str(move_data.get("mode", "")) == "ADVANCE":
		# Turbo Boostas replaces M with a flat 24" (fly modifier is moot,
		# matching _resolve_advance_roll where turbo overrides after the cap).
		if move_data.get("turbo_boost", false):
			m = 24.0
		return m + float(move_data.get("advance_roll", 0))
	return m

func _path_crosses_titanic_bases(from: Vector2, to: Vector2, unit_id: String, model: Dictionary) -> bool:
	# OA-29: Check if path crosses any TITANIC model bases (friendly or enemy).
	# Stompin' Forward units can move over everything EXCEPT TITANIC models.
	var units = game_state_snapshot.get("units", {})

	var reference_model = model.duplicate()

	var path_length = from.distance_to(to)
	var num_samples = max(2, int(path_length / 10.0))

	for i in range(num_samples + 1):
		var t = float(i) / float(num_samples)
		var sample_pos = from.lerp(to, t)

		var model_at_pos = reference_model.duplicate()
		model_at_pos["position"] = sample_pos

		for check_unit_id in units:
			if check_unit_id == unit_id:
				continue  # Skip own unit's models

			var check_unit = units[check_unit_id]
			var check_keywords = check_unit.get("meta", {}).get("keywords", [])
			var is_titanic = false
			for kw in check_keywords:
				if kw.to_upper() == "TITANIC":
					is_titanic = true
					break
			if not is_titanic:
				continue

			var check_models = check_unit.get("models", [])
			for check_model in check_models:
				if not check_model.get("alive", true):
					continue
				var check_pos = _get_model_position(check_model)
				if check_pos:
					if Measurement.models_overlap(model_at_pos, check_model):
						log_phase_message("  Path crosses TITANIC model base in unit %s" % check_unit_id)
						return true

	return false

func _get_terrain_height_inches(terrain_piece: Dictionary) -> float:
	# OA-28: Convert terrain height_category to inches for Clankin' Forward check
	# LOW (<2") = 1.5", MEDIUM (2-5") = 3.5", TALL (>5") = 6.0"
	var height_cat = terrain_piece.get("height_category", "tall")
	match height_cat:
		"low":
			return 1.5
		"medium":
			return 3.5
		"tall":
			return 6.0
		_:
			return 6.0  # Default to tall

# Speedwaaagh! Kustom Shokk Box: Deffkilla Wartrike model only. Each time the
# bearer uses its turbo, its unit can move horizontally through terrain
# features. Turbo is not a distinct modelled action (it is an Advance variant),
# so the bearer is treated as ignoring horizontal terrain restrictions for its
# moves: the 13.06 dense-terrain block is bypassed on an Advance (see
# _validate_set_model_dest) and the difficult-ground penalty is waived here.
func _unit_has_enhancement(unit_id: String, enh_name: String) -> bool:
	if unit_id == "":
		return false
	var target := enh_name.strip_edges().to_lower()
	var u = GameState.get_unit(unit_id)
	for e in u.get("meta", {}).get("enhancements", []):
		var nm = e if e is String else (e.get("name", "") if e is Dictionary else "")
		if String(nm).strip_edges().to_lower() == target:
			return true
	return false


func _unit_has_kustom_shokk_box(unit_id: String) -> bool:
	return _unit_has_enhancement(unit_id, "Kustom Shokk Box")


func _get_movement_terrain_penalty(from_pos: Vector2, to_pos: Vector2, unit_id: String, log_it: bool = true) -> float:
	# Calculate terrain penalty for movement.
	# - Difficult ground: flat 2" per piece crossed (TerrainManager).
	# - Vertical climb (T-103): per-segment vertical inches added when the
	#   destination overlaps a multi-floor terrain piece (height_inches > 0)
	#   and the unit is not on its ground floor already.
	# FLY units ignore both penalties (return 0).
	if _unit_has_fly_keyword(unit_id):
		return 0.0
	# Kustom Shokk Box (Speedwaaagh!): the bearer moves through terrain features,
	# so it pays no horizontal difficult-ground penalty.
	if _unit_has_kustom_shokk_box(unit_id):
		return 0.0
	var penalty = 0.0
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if terrain_manager and terrain_manager.has_method("calculate_movement_terrain_penalty"):
		# Pass the unit's keywords so INFANTRY (and anything that can move through
		# the piece) are not charged the ruins/difficult-ground penalty — 10e: they
		# move through walls/floors freely. FLY is already handled above.
		var _mv_unit = get_unit(unit_id) if unit_id != "" else {}
		var _mv_keywords = _mv_unit.get("meta", {}).get("keywords", []) if not _mv_unit.is_empty() else []
		penalty += float(terrain_manager.calculate_movement_terrain_penalty(from_pos, to_pos, false, _mv_keywords))
	# T-103: multi-floor vertical climb cost.
	# (WP-M4c GRAPNEL LAUNCHERS, Reiver Squad: "ignore all vertical distance" — SMAbilitiesC.)
	if not load("res://scripts/codex/space_marines/SMAbilitiesC.gd").ignores_vertical_distance(unit_id):
		penalty += _get_vertical_climb_cost(from_pos, to_pos, unit_id)
	# log_it=false is for the live drag preview (MovementController calls this
	# once per mouse-motion event so its ghost, its over-range clamp and this
	# validation all cost a move identically). Logging there would flood the
	# phase log with a line per frame; the authoritative validation call still
	# logs, so the drop that lands is still traceable.
	if log_it and penalty > 0.0:
		log_phase_message("  Terrain penalty: %.1f\" (incl vertical, FLY=false)" % penalty)
	return penalty


func _get_vertical_climb_cost(from_pos: Vector2, to_pos: Vector2, unit_id: String = "") -> float:
	# T-103: returns vertical inches the model must climb when moving onto a
	# multi-floor ruin. Uses TerrainManager.get_terrain_at_position(pos) +
	# get_height_inches() (height_category → 1.5/3.5/6.0). Descent is free
	# per 10e (10e treats vertical descent as part of the move at no extra
	# inches — only ascent costs).
	var tm = get_node_or_null("/root/TerrainManager")
	if tm == null:
		return 0.0
	if not (tm.has_method("get_terrain_at_position") and tm.has_method("get_height_inches")):
		return 0.0
	var from_t = tm.get_terrain_at_position(from_pos)
	var to_t = tm.get_terrain_at_position(to_pos)
	# 10e: units that can traverse the destination terrain (INFANTRY through
	# ruins per can_move_through) stay on the ground floor — no climb cost.
	# Without this, a 4" move onto a tall (6") ruin was inflated by +6" and
	# rejected as "exceeds cap", silently snapping the model back.
	if unit_id != "" and not to_t.is_empty() and tm.has_method("can_unit_move_through_terrain"):
		var unit = get_unit(unit_id)
		var keywords = unit.get("meta", {}).get("keywords", []) if not unit.is_empty() else []
		if tm.can_unit_move_through_terrain(keywords, to_t):
			return 0.0
	var from_h = 0.0
	var to_h = 0.0
	if not from_t.is_empty():
		from_h = float(tm.get_height_inches(from_t))
	if not to_t.is_empty():
		to_h = float(tm.get_height_inches(to_t))
	if to_h <= from_h:
		return 0.0  # Going level or downward (10e: descent is free)
	return to_h - from_h

func _path_crosses_enemy_bases(from: Vector2, to: Vector2, unit_id: String, model: Dictionary) -> bool:
	# Check if a movement path crosses any enemy model bases using shape-aware overlap.
	# 10e Rule: A model cannot move through enemy models during Normal Move or Advance.
	# Only Fall Back and FLY units may move through enemy models.
	# This checks base-to-base overlap only — moving *near* enemies is fine,
	# moving *through* their bases is not.
	# Reactive moves (Krump and Run, Scatter!, Codex: Orks (11e) follow-ups) are
	# made by the NON-active player's unit: its enemies are the active player's.
	# Codex: Adeptus Custodes CALISTUS ka'tah (CustodesKatah.gd): this unit's
	# normal / advance / fall-back move can move through all types of model.
	if _cus11e_moves_through_all_models(unit_id):
		return false
	# 24.35 SUPER-HEAVY WALKER: only TITANIC enemy models block the move.
	var shw_only_titanic := _shw_moves_through_models(unit_id)
	if shw_only_titanic:
		log_phase_message("  24.35 SUPER-HEAVY WALKER — %s may move through enemy models except TITANIC ones" % unit_id)
	var current_player = _reactive_move_owner if _reactive_move_owner > 0 else get_current_player()
	var units = game_state_snapshot.get("units", {})

	# Build a reference model for path sampling
	var reference_model = model.duplicate()

	# Sample points along the path (approximately every 10 pixels for good coverage)
	var path_length = from.distance_to(to)
	var num_samples = max(2, int(path_length / 10.0))

	for i in range(num_samples + 1):
		var t = float(i) / float(num_samples)
		var sample_pos = from.lerp(to, t)

		# Create a temporary model at this position
		var model_at_pos = reference_model.duplicate()
		model_at_pos["position"] = sample_pos

		# Check against all enemy models only (friendly models can be crossed freely)
		for enemy_unit_id in units:
			var enemy_unit = units[enemy_unit_id]
			if enemy_unit.get("owner", 0) == current_player:
				continue
			if shw_only_titanic and not _unit_is_titanic(enemy_unit):
				continue

			var enemy_models = enemy_unit.get("models", [])
			for enemy_model in enemy_models:
				if not enemy_model.get("alive", true):
					continue
				var enemy_pos = _get_model_position(enemy_model)
				if enemy_pos:
					# Only check base overlap — moving close to enemies is allowed,
					# only moving through their bases is illegal
					if Measurement.models_overlap(model_at_pos, enemy_model):
						return true

	return false

func _path_crosses_monster_vehicle_bases(from: Vector2, to: Vector2, unit_id: String, model: Dictionary) -> bool:
	# 10e Errata: No model can move across MONSTER or VEHICLE models (friendly or enemy)
	# unless the moving model has the FLY keyword (FLY check done by caller).
	# This checks all units on the board for MONSTER/VEHICLE keyword and blocks
	# path crossing through their bases, excluding the moving unit's own models.
	# Codex: Adeptus Custodes CALISTUS (CustodesKatah.gd): "all types of model".
	if _cus11e_moves_through_all_models(unit_id):
		return false
	# 24.35 SUPER-HEAVY WALKER: MONSTER / VEHICLE models no longer block the
	# move — only TITANIC ones do (friendly or enemy).
	var shw_only_titanic := _shw_moves_through_models(unit_id)
	var units = game_state_snapshot.get("units", {})

	var reference_model = model.duplicate()

	# Sample points along the path (approximately every 10 pixels for good coverage)
	var path_length = from.distance_to(to)
	var num_samples = max(2, int(path_length / 10.0))

	for i in range(num_samples + 1):
		var t = float(i) / float(num_samples)
		var sample_pos = from.lerp(to, t)

		var model_at_pos = reference_model.duplicate()
		model_at_pos["position"] = sample_pos

		for check_unit_id in units:
			if check_unit_id == unit_id:
				continue  # Skip own unit's models

			var check_unit = units[check_unit_id]
			if shw_only_titanic and not _unit_is_titanic(check_unit):
				continue
			# Only block on MONSTER or VEHICLE units
			var check_keywords = check_unit.get("meta", {}).get("keywords", [])
			var is_monster_or_vehicle = false
			for kw in check_keywords:
				var kw_upper = kw.to_upper()
				if kw_upper == "MONSTER" or kw_upper == "VEHICLE":
					is_monster_or_vehicle = true
					break
			if not is_monster_or_vehicle:
				continue

			var check_models = check_unit.get("models", [])
			for check_model in check_models:
				if not check_model.get("alive", true):
					continue
				var check_pos = _get_model_position(check_model)
				if check_pos:
					if Measurement.models_overlap(model_at_pos, check_model):
						log_phase_message("  Path crosses MONSTER/VEHICLE model base in unit %s" % check_unit_id)
						return true

	return false

func _path_crosses_enemy(from: Vector2, to: Vector2, unit_id: String, base_mm: int) -> bool:
	# Legacy wrapper for Fall Back path checking (keeps crosses_enemy tracking for Desperate Escape)
	# Fall Back moves are allowed to cross enemies, so this is used for tracking, not blocking
	var units = game_state_snapshot.get("units", {})
	var unit = units.get(unit_id, {})
	var reference_model = null
	for m in unit.get("models", []):
		if m.get("alive", true):
			reference_model = m.duplicate()
			break
	if reference_model == null:
		return false
	return _path_crosses_enemy_bases(from, to, unit_id, reference_model)

func _segment_intersects_circle(seg_start: Vector2, seg_end: Vector2, circle_center: Vector2, radius: float) -> bool:
	# Calculate closest point on segment to circle center
	var seg_vec = seg_end - seg_start
	var to_center = circle_center - seg_start
	var t = clamp(to_center.dot(seg_vec) / seg_vec.length_squared(), 0.0, 1.0)
	var closest_point = seg_start + seg_vec * t
	var distance = closest_point.distance_to(circle_center)
	return distance <= radius

func _position_overlaps_other_models(unit_id: String, model_id: String, position: Vector2, model_data: Dictionary = {}) -> bool:
	# Check if a position would overlap with any other models
	# Returns true if there's an overlap (invalid position)
	var units = game_state_snapshot.get("units", {})

	# Build a model dict for the checking position
	var check_model = model_data.duplicate() if not model_data.is_empty() else _get_model_in_unit(unit_id, model_id)
	check_model["position"] = position

	# Settings › Gameplay › vehicle collision override: a VEHICLE's base may
	# overlap anything, so the mover being one clears every pair at once.
	if SettingsService.unit_skips_collision(unit_id):
		return false

	for check_unit_id in units:
		var unit = units[check_unit_id]
		# The override also exempts pairs where only the OTHER model is a
		# VEHICLE, so infantry can still be placed against a parked Stompa.
		if SettingsService.unit_skips_collision(check_unit_id):
			continue
		# Check models in all units (friendly and enemy)
		var models = unit.get("models", [])

		for i in range(models.size()):
			var other_model = models[i]
			var other_model_id = other_model.get("id", "m%d" % (i+1))

			# Skip self
			if check_unit_id == unit_id and other_model_id == model_id:
				continue

			# Skip dead models
			if not other_model.get("alive", true):
				continue

			# Get the current position of the other model — its staged destination
			# if it already has one this move, else its board position.
			# An attached character's staged moves live in the BODYGUARD unit's
			# move data (active_moves is keyed by the unit making the move), so
			# active_moves[check_unit_id] finds nothing for the character's own
			# unit id and every other model was checked against the spot he had
			# already VACATED. Scan all live moves and match on
			# model_source_unit_id, which also keeps a character's "m1" from being
			# read as the bodyguard's "m1".
			var other_position = null
			for owner_unit_id in active_moves:
				for staged_move in active_moves[owner_unit_id].get("staged_moves", []):
					if str(staged_move.get("model_id", "")) != str(other_model_id):
						continue
					if str(staged_move.get("model_source_unit_id", owner_unit_id)) != str(check_unit_id):
						continue
					other_position = staged_move.get("dest")
					break
				if other_position != null:
					break

			# If no staged position, use actual position
			if other_position == null:
				other_position = _get_model_position(other_model)

			if other_position == null:
				continue

			# Build other model dict with correct position
			var other_model_check = other_model.duplicate()
			other_model_check["position"] = other_position

			# Check for overlap using the Measurement utility
			if Measurement.models_overlap(check_model, other_model_check):
				# Reject sub-pixel false-positives at the touching boundary.
				# For circular-vs-circular we can do an exact tolerance check;
				# other shape combinations keep strict behavior.
				if _is_touching_within_tolerance(check_model, other_model_check):
					continue
				var _op = other_position if other_position is Vector2 else Vector2(other_position.get("x", 0), other_position.get("y", 0))
				DebugLogger.info("OVERLAP_DEBUG %s.%s at (%.0f,%.0f) overlaps %s.%s at (%.0f,%.0f) dist=%.1fpx" % [
					unit_id, model_id, position.x, position.y,
					check_unit_id, other_model_id, _op.x, _op.y, position.distance_to(_op)])
				return true

	return false

func _is_touching_within_tolerance(model_a: Dictionary, model_b: Dictionary) -> bool:
	if model_a.get("base_type", "circular") != "circular":
		return false
	if model_b.get("base_type", "circular") != "circular":
		return false
	var pos_a = model_a.get("position", Vector2.ZERO)
	var pos_b = model_b.get("position", Vector2.ZERO)
	if pos_a is Dictionary:
		pos_a = Vector2(pos_a.get("x", 0), pos_a.get("y", 0))
	if pos_b is Dictionary:
		pos_b = Vector2(pos_b.get("x", 0), pos_b.get("y", 0))
	var radius_a = Measurement.base_radius_px(model_a.get("base_mm", 32))
	var radius_b = Measurement.base_radius_px(model_b.get("base_mm", 32))
	var center_distance = pos_a.distance_to(pos_b)
	return center_distance + OVERLAP_TOLERANCE_PX >= (radius_a + radius_b)

func _position_intersects_terrain(pos: Vector2, model: Dictionary, max_passable_height: float = 0.0) -> bool:
	# Check against terrain polygons using shape-aware bounds
	# OA-28: max_passable_height > 0 means terrain at or below that height (inches) is ignored
	# (used by Clankin' Forward to allow moving over terrain ≤4")
	var terrain = game_state_snapshot.get("board", {}).get("terrain", [])

	# Create the base shape to get accurate bounds
	var base_shape = Measurement.create_base_shape(model)
	var bounds = base_shape.get_bounds()

	# Use the maximum dimension of the bounds as the expansion
	# This provides better coverage for non-circular bases
	var expansion = max(bounds.size.x, bounds.size.y) / 2.0

	for terrain_piece in terrain:
		if terrain_piece.get("type", "") == "impassable":
			# OA-28: Skip terrain that is short enough for Clankin' Forward
			if max_passable_height > 0.0:
				var terrain_height = _get_terrain_height_inches(terrain_piece)
				if terrain_height <= max_passable_height:
					continue
			# Issue #385: TerrainManager stores polygon as "polygon"; older code
			# read "poly". Try both keys for compatibility.
			var poly = terrain_piece.get("polygon", terrain_piece.get("poly", []))
			if _point_in_expanded_polygon(pos, poly, expansion):
				return true

	return false

func _position_outside_board_bounds(pos: Vector2, model: Dictionary) -> bool:
	# Check if any part of the model's base would extend beyond the board edges
	# Rule: No part of a model (including its base) can cross the edge of the battlefield
	var board_size = game_state_snapshot.get("board", {}).get("size", {})
	var board_width_inches = board_size.get("width", 44.0)
	var board_height_inches = board_size.get("height", 60.0)
	var board_width_px = Measurement.inches_to_px(board_width_inches)
	var board_height_px = Measurement.inches_to_px(board_height_inches)

	# Get the model's base radius in pixels
	var base_shape = Measurement.create_base_shape(model)
	var bounds = base_shape.get_bounds()
	var half_width = bounds.size.x / 2.0
	var half_height = bounds.size.y / 2.0

	# Check if any edge of the base extends beyond the board
	if pos.x - half_width < 0 or pos.x + half_width > board_width_px:
		return true
	if pos.y - half_height < 0 or pos.y + half_height > board_height_px:
		return true

	return false

func _point_in_expanded_polygon(point: Vector2, poly: Array, expansion: float) -> bool:
	# Simple point-in-polygon test with expansion
	# For MVP, treat as rectangle bounds check
	if poly.is_empty():
		return false
	
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	
	for vertex in poly:
		min_x = min(min_x, vertex.x)
		max_x = max(max_x, vertex.x)
		min_y = min(min_y, vertex.y)
		max_y = max(max_y, vertex.y)
	
	return point.x >= (min_x - expansion) and point.x <= (max_x + expansion) and \
		   point.y >= (min_y - expansion) and point.y <= (max_y + expansion)

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

func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

func _reset_staged_visuals_if_needed(unit_id: String) -> void:
	"""If a unit has staged (uncommitted) moves, reset visual tokens to GameState positions.
	This prevents visual/GameState desync when switching movement modes (e.g. Normal -> Advance)."""
	if not active_moves.has(unit_id):
		return
	var move_data = active_moves[unit_id]
	if move_data.staged_moves.size() > 0:
		DebugLogger.info(str("[MovementPhase] Resetting staged visuals for %s (had %d staged moves)" % [unit_id, move_data.staged_moves.size()]))
		# Reset each staged model's visual back to its GameState position and rotation
		for staged_move in move_data.staged_moves:
			var model = _get_model_in_unit(unit_id, staged_move.model_id)
			if not model.is_empty():
				var gs_pos = _get_model_position(model)
				var gs_rotation = model.get("rotation", 0.0)
				emit_signal("model_drop_committed", unit_id, staged_move.model_id, gs_pos, gs_rotation)
		# Also emit unit_move_reset so controller clears its state
		emit_signal("unit_move_reset", unit_id)

func _clear_unit_move_state(unit_id: String) -> void:
	if active_moves.has(unit_id):
		active_moves.erase(unit_id)

## Codex: Adeptus Custodes (11e) Lightning Descent: the reserve units of
## `player` that may arrive in battle round 1 (WP-C46).
func _cus11e_lightning_descent_reserves(player: int) -> Array:
	var out: Array = []
	if GameConstants.edition < 11:
		return out
	for rid in GameState.get_reserves_for_player(player):
		if _cus11e_det().can_ingress_first_round(get_unit(str(rid))):
			out.append(rid)
		elif load("res://scripts/codex/space_marines/SMDetachmentsB.gd").can_ingress_first_round(get_unit(str(rid))):  # WP-M2b Corporeum Reliquary (Codex: Space Marines 11e)
			out.append(rid)
	# WP-S4 HIGH KING OF FENRIS (Space Wolves): the selected unit can arrive in battle round 1.
	for hk_id in _sw11e_abilities().high_king_first_round_units(player):
		if not hk_id in out:
			out.append(hk_id)
	# WP-M4a DROP POD ASSAULT: Drop Pods can arrive in their player's first Movement phase.
	for rid in GameState.get_reserves_for_player(player):
		if _sm11e_abilities_a().can_ingress_first_round(get_unit(str(rid))) and not rid in out:
			out.append(rid)
	return out

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)

	# Add reinforcement actions for units in reserves (from Turn 2 onwards)
	var battle_round = GameState.get_battle_round()
	print("MovementPhase: get_available_actions — battle_round=%d, current_player=%d" % [battle_round, current_player])
	# Codex: Adeptus Custodes (11e) Lightning Descent (WP-C46): the bearer's
	# unit can make an ingress move in its player's FIRST Movement phase.
	# WP-O5 Impulsive Recon: so can those ORKS AIRCRAFT.
	var cus11e_ld_reserves: Array = _cus11e_lightning_descent_reserves(current_player) if battle_round < 2 else []
	if battle_round < 2:
		for o5_uid in load("res://scripts/codex/orks/OrkEnhancements11e.gd").first_round_ingress_units(GameState.get_reserves_for_player(current_player)):
			if not o5_uid in cus11e_ld_reserves:
				cus11e_ld_reserves.append(o5_uid)
	if battle_round >= 2 or not cus11e_ld_reserves.is_empty():
		var reserves = GameState.get_reserves_for_player(current_player) if battle_round >= 2 else cus11e_ld_reserves
		print("MovementPhase: Found %d reserve units for player %d: %s" % [reserves.size(), current_player, str(reserves)])
		for reserve_unit_id in reserves:
			var reserve_unit = get_unit(reserve_unit_id)

			# Skip attached characters — they arrive with their bodyguard automatically
			var attached_to = reserve_unit.get("attached_to", "")
			if attached_to != null and attached_to != "":
				continue

			var reserve_name = reserve_unit.get("meta", {}).get("name", reserve_unit_id)
			var reserve_type = reserve_unit.get("reserve_type", "strategic_reserves")
			var type_label = "Deep Strike" if reserve_type == "deep_strike" else "Reserves"

			# Show attached characters in the description
			var attachment_data = reserve_unit.get("attachment_data", {})
			var attached_chars = attachment_data.get("attached_characters", [])
			var char_names = []
			for char_id in attached_chars:
				var char_unit = get_unit(char_id)
				if char_unit.get("status", 0) == GameStateData.UnitStatus.IN_RESERVES:
					char_names.append(char_unit.get("meta", {}).get("name", char_id))
			var char_suffix = ""
			if char_names.size() > 0:
				char_suffix = " + " + ", ".join(char_names)

			# P2-80: Flag units that can choose between Deep Strike and Strategic Reserves placement
			var has_ds_choice = false
			if reserve_type == "strategic_reserves" and GameState.unit_has_deep_strike(reserve_unit_id):
				has_ds_choice = true
				type_label = "Reserves (DS/SR choice)"

			actions.append({
				"type": "PLACE_REINFORCEMENT",
				"unit_id": reserve_unit_id,
				"description": "Arrive from %s: %s%s" % [type_label, reserve_name, char_suffix],
				"has_ds_choice": has_ds_choice
			})

	# Debug: Log all units and their embarked status for transport diagnostics
	DebugLogger.info(str("MovementPhase: get_available_actions — checking %d units for player %d" % [units.size(), current_player]))
	for dbg_id in units:
		var dbg_unit = units[dbg_id]
		var dbg_name = dbg_unit.get("meta", {}).get("name", dbg_id)
		var dbg_status = dbg_unit.get("status", -1)
		var dbg_embarked = dbg_unit.get("embarked_in", null)
		var dbg_transport_data = dbg_unit.get("transport_data", {})
		var dbg_embarked_units = dbg_transport_data.get("embarked_units", []) if dbg_transport_data else []
		if dbg_embarked != null or dbg_embarked_units.size() > 0:
			DebugLogger.info(str("MovementPhase:   TRANSPORT-RELATED: %s (id=%s) status=%d embarked_in=%s embarked_units=%s" % [dbg_name, dbg_id, dbg_status, str(dbg_embarked), str(dbg_embarked_units)]))

	for unit_id in units:
		var unit = units[unit_id]
		# Embarked units may have incorrect UNDEPLOYED status due to formations phase;
		# treat them as deployed so they can disembark
		var is_embarked = unit.get("embarked_in", null) != null
		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED and not is_embarked:
			continue

		# 19.03: an attached CHARACTER disembarks with the unit it leads, so it
		# gets no row of its own — the bodyguard's "Boyz + Warboss" row covers
		# both. (This guard must sit above the embarked branch: without it the
		# leader showed up as a second, separately-disembarkable unit.)
		if unit.get("attached_to", null) != null:
			continue

		# P3-32: Embarked units get disembark option instead of normal movement
		if is_embarked:
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			var transport_id = unit.embarked_in
			var transport = get_unit(transport_id)
			var transport_name = transport.get("meta", {}).get("name", transport_id) if transport else transport_id
			DebugLogger.info(str("MovementPhase: Found embarked unit %s (id=%s) in transport %s (id=%s)" % [unit_name, unit_id, transport_name, transport_id]))
			# Check if disembark is valid (transport hasn't Advanced/Fell Back)
			var can_disembark_result = TransportManager.can_disembark(unit_id)
			DebugLogger.info(str("MovementPhase: can_disembark result for %s: %s" % [unit_name, str(can_disembark_result)]))
			if can_disembark_result.valid:
				actions.append({
					"type": "DISEMBARK_UNIT",
					"actor_unit_id": unit_id,
					"description": "Disembark %s from %s" % [unit_name, transport_name]
				})
				DebugLogger.info(str("MovementPhase: Added DISEMBARK_UNIT action for %s" % unit_name))
			else:
				# Still show the unit in the list so user can see it, but mark as blocked
				actions.append({
					"type": "DISEMBARK_BLOCKED",
					"actor_unit_id": unit_id,
					"description": "%s (Embarked in %s — %s)" % [unit_name, transport_name, can_disembark_result.get("reason", "cannot disembark")]
				})
				DebugLogger.info(str("MovementPhase: Disembark not valid for %s — reason: %s (still adding to list as blocked)" % [unit_name, can_disembark_result.get("reason", "unknown")]))
			continue

		# Skip if already moved
		if unit.get("flags", {}).get("moved", false):
			continue

		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var is_engaged = _is_unit_engaged(unit_id)

		if is_engaged:
			# Can only Fall Back or Remain Stationary when engaged
			actions.append({
				"type": "BEGIN_FALL_BACK",
				"actor_unit_id": unit_id,
				"description": "Fall Back with " + unit_name
			})
			actions.append({
				"type": "REMAIN_STATIONARY",
				"actor_unit_id": unit_id,
				"description": unit_name + " remains stationary"
			})
		else:
			# Normal movement options
			actions.append({
				"type": "BEGIN_NORMAL_MOVE",
				"actor_unit_id": unit_id,
				"description": "Move " + unit_name
			})
			actions.append({
				"type": "BEGIN_ADVANCE",
				"actor_unit_id": unit_id,
				"description": "Advance with " + unit_name
			})
			actions.append({
				"type": "REMAIN_STATIONARY",
				"actor_unit_id": unit_id,
				"description": unit_name + " remains stationary"
			})

	# Add active move actions (skip completed moves)
	# Use synced GameState flags.moved to determine completion for multiplayer compatibility
	for unit_id in active_moves:
		var unit_check = get_unit(unit_id)
		if unit_check.get("flags", {}).get("moved", false):
			continue
		actions.append({
			"type": "CONFIRM_UNIT_MOVE",
			"actor_unit_id": unit_id,
			"description": "Confirm move"
		})
		actions.append({
			"type": "RESET_UNIT_MOVE",
			"actor_unit_id": unit_id,
			"description": "Reset move"
		})
		if not active_moves[unit_id].model_moves.is_empty() or not active_moves[unit_id].staged_moves.is_empty():
			actions.append({
				"type": "UNDO_LAST_MODEL_MOVE",
				"actor_unit_id": unit_id,
				"description": "Undo last model"
			})
	
	# Add End Movement Phase action if no incomplete moves
	# Check using synced GameState flags for multiplayer compatibility (T2-12 fix)
	var has_incomplete_moves = false
	log_phase_message("[get_available_actions] Checking if END_MOVEMENT should be available...")
	log_phase_message("[get_available_actions] Active moves (local): %s" % str(active_moves.keys()))

	# Check local active_moves against synced GameState
	for unit_id in active_moves:
		var unit = get_unit(unit_id)
		var has_moved = unit.get("flags", {}).get("moved", false)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		log_phase_message("[get_available_actions]   Unit %s (%s): flags.moved = %s" % [unit_id, unit_name, str(has_moved)])
		if not has_moved:
			has_incomplete_moves = true
			log_phase_message("[get_available_actions]   → This unit has incomplete moves!")
			break

	# Also check GameState for any units with movement_active flag set
	# This catches cases where the client's active_moves is out of sync (T2-12)
	if not has_incomplete_moves:
		var all_units = get_units_for_player(current_player)
		for unit_id in all_units:
			var unit = all_units[unit_id]
			if unit.get("flags", {}).get("movement_active", false) and not unit.get("flags", {}).get("moved", false):
				has_incomplete_moves = true
				var unit_name = unit.get("meta", {}).get("name", unit_id)
				log_phase_message("[get_available_actions]   → GameState flags show %s (%s) has active movement!" % [unit_id, unit_name])
				break

	if not has_incomplete_moves:
		log_phase_message("[get_available_actions] ✓ Adding END_MOVEMENT action")
		actions.append({
			"type": "END_MOVEMENT",
			"description": "End Movement Phase"
		})
	else:
		log_phase_message("[get_available_actions] ✗ NOT adding END_MOVEMENT (incomplete moves exist)")
	
	# ISS-040 step 2: at edition >= 11 the MoveType registry (09.04-09.07
	# templates) is authoritative for the four basic moves — offerings the
	# templates rule ineligible are dropped. Ability extras (infiltrator
	# redeploys, reinforcements, disembarks) pass through.
	if GameConstants.edition >= 11:
		var basic_map = {"BEGIN_NORMAL_MOVE": "normal", "BEGIN_ADVANCE": "advance",
			"BEGIN_FALL_BACK": "fall_back", "REMAIN_STATIONARY": "remain_stationary"}
		var type_for_mt = {"normal": "BEGIN_NORMAL_MOVE", "advance": "BEGIN_ADVANCE",
			"fall_back": "BEGIN_FALL_BACK", "remain_stationary": "REMAIN_STATIONARY"}
		var label_for_mt = {"normal": "Move", "advance": "Advance with",
			"fall_back": "Fall Back with", "remain_stationary": "Remain stationary:"}
		var avail_cache: Dictionary = {}
		var offered: Dictionary = {}
		var filtered: Array = []
		for a in actions:
			var t = str(a.get("type", ""))
			if basic_map.has(t):
				var uid = str(a.get("actor_unit_id", ""))
				if not avail_cache.has(uid):
					avail_cache[uid] = MoveTypes.available_for(uid, GameState.state)
					print("MovementPhase: [11e] MoveTypes.available_for(%s) -> %s" % [uid, str(avail_cache[uid])])
				if not basic_map[t] in avail_cache[uid]:
					continue
				offered["%s:%s" % [uid, basic_map[t]]] = true
			filtered.append(a)
		# Audit #8 (21.02): offer a surge move to every current-player unit
		# whose datasheet grants one ("Surge X\"" ability) and that the
		# template rules eligible. No shipped datasheet carries one yet —
		# this is the player affordance the data lights up.
		for uid in GameState.state.get("units", {}):
			var surge_unit = get_unit(str(uid))
			if int(surge_unit.get("owner", 0)) != get_current_player():
				continue
			var surge_att = surge_unit.get("attached_to", null)
			var surge_emb = surge_unit.get("embarked_in", null)
			if (surge_att != null and str(surge_att) != "") or (surge_emb != null and str(surge_emb) != ""):
				continue
			var surge_inches = RulesEngine.get_surge_move_inches(surge_unit)
			if surge_inches > 0.0 and MoveTypes.get_type("surge").eligible(str(uid), GameState.state).eligible:
				filtered.append({
					"type": "BEGIN_SURGE_MOVE",
					"actor_unit_id": str(uid),
					"description": "Surge %0.0f\" toward the closest enemy: %s" % [surge_inches, surge_unit.get("meta", {}).get("name", uid)]
				})
		# Top-up: basics the templates deem eligible that the 10e builder
		# did not offer (e.g. engagement state divergence). Only units the
		# builder considered movable (present in avail_cache) qualify.
		for uid in avail_cache:
			var u_name = get_unit(uid).get("meta", {}).get("name", uid)
			for mt_id in avail_cache[uid]:
				if not offered.has("%s:%s" % [uid, mt_id]):
					filtered.append({
						"type": type_for_mt[mt_id],
						"actor_unit_id": uid,
						"description": "%s %s" % [label_for_mt[mt_id], u_name]
					})
					print("MovementPhase: [11e] top-up offering %s for %s" % [type_for_mt[mt_id], uid])
		return filtered

	return actions

func _should_complete_phase() -> bool:
	# Movement phase should NOT auto-complete
	# Phase completion must be explicit via END_MOVEMENT action for:
	# 1. User control - player may want to use stratagems before ending phase
	# 2. Multiplayer sync - phase transitions must be synchronized via actions
	return false

func get_dice_log() -> Array:
	return dice_log

func get_active_move_data(unit_id: String) -> Dictionary:
	# Helper method for MovementController to access active move data
	if active_moves.has(unit_id):
		return active_moves[unit_id]
	return {}

func _check_active_moves_sync() -> void:
	# T2-12: Debug consistency check between local active_moves and synced GameState
	# Call this periodically or after action processing to detect desync
	for unit_id in active_moves:
		var unit = get_unit(unit_id)
		var local_completed = active_moves[unit_id].get("completed", false)
		var synced_moved = unit.get("flags", {}).get("moved", false)
		var synced_active = unit.get("flags", {}).get("movement_active", false)

		# If local says completed but GameState says not moved, we have a desync
		if local_completed and not synced_moved:
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			log_phase_message("WARNING: MULTIPLAYER DESYNC DETECTED for %s (%s) - local completed=%s, GameState moved=%s" % [unit_id, unit_name, local_completed, synced_moved])

		# If local has active move but GameState doesn't show movement_active
		if not local_completed and not synced_active and not synced_moved:
			var unit_name = unit.get("meta", {}).get("name", unit_id)
			log_phase_message("WARNING: MULTIPLAYER DESYNC DETECTED for %s (%s) - local has active move but GameState movement_active=%s" % [unit_id, unit_name, synced_active])

# GROUP MOVEMENT VALIDATION FUNCTIONS

func _process_group_movement(selected_models: Array, drag_vector: Vector2, unit_id: String) -> Dictionary:
	"""Process and validate group movement for multiple models"""
	var group_validation = {"valid": true, "errors": [], "individual_distances": {}}

	if not active_moves.has(unit_id):
		group_validation.valid = false
		group_validation.errors.append("No active move data for unit")
		return group_validation

	var move_data = active_moves[unit_id]
	var move_cap_inches = move_data.move_cap_inches

	for model_data in selected_models:
		var model_id = model_data.model_id
		var model_source = model_data.get("unit_id", unit_id)
		var model_key = "%s:%s" % [model_source, model_id]
		var original_pos = move_data.original_positions.get(model_key, model_data.position)
		var new_pos = model_data.position + drag_vector

		# Calculate individual distance
		var total_distance = Measurement.distance_inches(original_pos, new_pos)
		# Add terrain elevation penalty: non-FLY units must count vertical distance for tall terrain
		# FLY units ignore terrain elevation entirely (penalty = 0)
		total_distance += _get_movement_terrain_penalty(original_pos, new_pos, unit_id)
		group_validation.individual_distances[model_id] = total_distance

		# Validate against movement cap (with floating-point tolerance)
		if total_distance > move_cap_inches + MOVEMENT_CAP_EPSILON:
			group_validation.valid = false
			group_validation.errors.append("Model %s exceeds movement cap (%.1f\" > %.1f\")" % [model_id, total_distance, move_cap_inches])

		# Check for terrain collisions
		var full_model = _get_model_in_unit(unit_id, model_id)
		if not full_model.is_empty() and _check_terrain_collision(new_pos, full_model):
			group_validation.valid = false
			group_validation.errors.append("Model %s would collide with terrain" % model_id)

		# Check for model overlaps
		if _would_overlap_other_models(unit_id, model_id, new_pos, model_data):
			group_validation.valid = false
			group_validation.errors.append("Model %s would overlap with another model" % model_id)

		# 10e Rule: Normal Move and Advance cannot cross enemy model bases
		# FLY units are exempt — they can move over enemy models
		if move_data.mode in ["NORMAL", "ADVANCE"] and not _unit_has_fly_keyword(unit_id) and not _o6_moves_through_models(unit_id, move_data):
			if not full_model.is_empty() and _path_crosses_enemy_bases(model_data.position, new_pos, unit_id, full_model):
				group_validation.valid = false
				group_validation.errors.append("Model %s path crosses enemy model base" % model_id)

		# 10e Errata: Cannot move across MONSTER or VEHICLE models (friendly or enemy)
		# FLY units are exempt
		if not _unit_has_fly_keyword(unit_id) and not _o6_moves_through_models(unit_id, move_data):
			if not full_model.is_empty() and _path_crosses_monster_vehicle_bases(model_data.position, new_pos, unit_id, full_model):
				group_validation.valid = false
				group_validation.errors.append("Model %s path crosses Monster/Vehicle model base" % model_id)

	return group_validation

func _validate_group_movement(group_moves: Array, unit_id: String) -> Dictionary:
	"""Validate a group of movement actions for coherency and rule compliance"""
	var validation_result = {"valid": true, "errors": [], "warnings": []}

	if not active_moves.has(unit_id):
		validation_result.valid = false
		validation_result.errors.append("No active move data for unit")
		return validation_result

	var move_data = active_moves[unit_id]

	for move in group_moves:
		var model_id = move.get("model_id", "")
		var dest_pos = Vector2(move.get("dest", [0, 0])[0], move.get("dest", [0, 0])[1])

		# Individual validations
		if not _validate_individual_move_internal(unit_id, model_id, dest_pos):
			validation_result.valid = false
			validation_result.errors.append("Invalid move for model %s" % model_id)

	# Check unit coherency for the entire group
	if not _check_group_unit_coherency(group_moves, unit_id):
		validation_result.warnings.append("Group movement may break unit coherency")

	return validation_result

func _validate_individual_move_internal(unit_id: String, model_id: String, dest_pos: Vector2) -> bool:
	"""Internal validation for a single model move"""
	if not active_moves.has(unit_id):
		return false

	var move_data = active_moves[unit_id]
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])

	# Find the model
	var model = null
	for m in models:
		if m.get("id", "") == model_id:
			model = m
			break

	if not model:
		return false

	# Check distance limit (try composite key with unit_id, then attached chars)
	var validate_model_key = "%s:%s" % [unit_id, model_id]
	var original_pos = move_data.original_positions.get(validate_model_key)
	if original_pos == null:
		var attached_chars = unit.get("attachment_data", {}).get("attached_characters", [])
		for cid in attached_chars:
			var char_key = "%s:%s" % [cid, model_id]
			original_pos = move_data.original_positions.get(char_key)
			if original_pos != null:
				break
	if original_pos == null:
		original_pos = _get_model_position(model)
	var total_distance = Measurement.distance_inches(original_pos, dest_pos)
	# Add terrain penalty (difficult ground only — no height penalty, units stay on ground floor)
	total_distance += _get_movement_terrain_penalty(original_pos, dest_pos, unit_id)

	if total_distance > move_data.move_cap_inches:
		return false

	# Check terrain collision
	if _check_terrain_collision(dest_pos, model):
		return false

	# Check model overlap
	if _would_overlap_other_models(unit_id, model_id, dest_pos, model):
		return false

	# 10e Rule: Normal Move and Advance cannot cross enemy model bases
	if move_data.mode in ["NORMAL", "ADVANCE"] and not _unit_has_fly_keyword(unit_id) and not _o6_moves_through_models(unit_id, move_data):
		var current_pos = _get_model_position(model)
		if current_pos and _path_crosses_enemy_bases(current_pos, dest_pos, unit_id, model):
			return false

	# 10e Errata: Cannot move across MONSTER or VEHICLE models (friendly or enemy)
	# FLY units are exempt
	if not _unit_has_fly_keyword(unit_id) and not _o6_moves_through_models(unit_id, move_data):
		var current_pos = _get_model_position(model)
		if current_pos and _path_crosses_monster_vehicle_bases(current_pos, dest_pos, unit_id, model):
			return false

	return true

func _check_group_unit_coherency(group_moves: Array, unit_id: String) -> bool:
	"""Check if a group of moves maintains unit coherency"""
	var unit = get_unit(unit_id)
	if not unit:
		return false

	var models = unit.get("models", [])
	if models.size() <= 1:
		return true  # Single model units are always coherent

	# Build model dicts with final positions for shape-aware distance checks
	var final_models = {}

	# Add model dicts for models not being moved
	for model in models:
		if not model.get("alive", true):
			continue
		var model_id = model.get("id", "")
		final_models[model_id] = model

	# Update positions for models being moved
	for move in group_moves:
		var model_id = move.get("model_id", "")
		var dest = move.get("dest", [0, 0])
		if final_models.has(model_id):
			var moved_model = final_models[model_id].duplicate()
			moved_model["position"] = Vector2(dest[0], dest[1])
			final_models[model_id] = moved_model

	# Check coherency via the edition-aware single source of truth (11e 03.03:
	# within 2" of a mate AND within 9" of every other model in the unit).
	return AttackSequence.check_unit_coherency({"models": final_models.values()}).get("coherent", true)

func _check_terrain_collision(position: Vector2, model: Dictionary) -> bool:
	"""Check if a position collides with impassable terrain using shape-aware bounds"""
	return _position_intersects_terrain(position, model)

func _would_overlap_other_models(unit_id: String, model_id: String, position: Vector2, model_data: Dictionary) -> bool:
	"""Check if placing a model at the given position would overlap with other models"""
	return _position_overlaps_other_models(unit_id, model_id, position, model_data)

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

# Transport-related methods

func _check_embark_opportunity(unit_id: String) -> void:
	"""Check if a unit that just moved can embark in a nearby transport"""
	# Skip embark prompts for AI players — AI doesn't use UI dialogs
	var ai_player = get_node_or_null("/root/AIPlayer")
	if ai_player and ai_player.is_ai_player(get_current_player()):
		return

	var unit = get_unit(unit_id)
	if not unit:
		return

	# Skip if unit is a transport itself
	if unit.has("transport_data"):
		return

	# Get unit's center position
	var unit_pos = _get_unit_center_position(unit_id)
	if unit_pos == Vector2.ZERO:
		return

	# Find friendly transports within 3"
	var player = unit.owner
	for transport_id in game_state_snapshot.units:
		var transport = game_state_snapshot.units[transport_id]

		# Skip if not same owner
		if transport.owner != player:
			continue

		# Skip if not a transport
		if not transport.has("transport_data") or transport.transport_data.get("capacity", 0) == 0:
			continue

		# Skip if transport is the same unit
		if transport_id == unit_id:
			continue

		# Get transport position
		var transport_pos = _get_unit_center_position(transport_id)
		if transport_pos == Vector2.ZERO:
			continue

		# P3-95: Use centralized shape-aware distance check from TransportManager
		var range_check = TransportManager.is_unit_within_embark_range(unit, transport)

		if range_check.within_range:
			# Check if unit can embark
			var can_embark = TransportManager.can_embark(unit_id, transport_id)
			if can_embark.valid:
				_show_embark_prompt(unit_id, transport_id)
				return  # Only show one prompt at a time

func _show_embark_prompt(unit_id: String, transport_id: String) -> void:
	"""Show dialog asking if player wants to embark unit.
	On confirm, routes through the action system via NetworkIntegration
	so the embark is validated and synchronized across all clients."""
	var dialog = ConfirmationDialog.new()
	var unit = get_unit(unit_id)
	var transport = get_unit(transport_id)

	dialog.title = "Embark Unit"
	dialog.dialog_text = "Do you want to embark %s into %s?" % [
		unit.meta.get("name", unit_id),
		transport.meta.get("name", transport_id)
	]

	dialog.get_ok_button().text = "Embark"
	dialog.get_cancel_button().text = "Stay Deployed"

	dialog.confirmed.connect(func():
		# Route through action system for network synchronization
		var action = {
			"type": "EMBARK_UNIT",
			"actor_unit_id": unit_id,
			"payload": {
				"transport_id": transport_id
			}
		}
		var result = NetworkIntegration.route_action(action)
		if not result.get("success", false) and not result.get("pending", false):
			log_phase_message("Embark action failed: %s" % str(result.get("errors", result.get("error", "unknown"))))
		dialog.queue_free()
	)

	dialog.canceled.connect(func():
		dialog.queue_free()
	)

	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)

func _get_unit_center_position(unit_id: String) -> Vector2:
	"""Get the center position of a unit (average of all alive models)"""
	var unit = get_unit(unit_id)
	if not unit:
		return Vector2.ZERO

	var center = Vector2.ZERO
	var count = 0

	for model in unit.models:
		if model.alive and model.position != null:
			center += Vector2(model.position.x, model.position.y)
			count += 1

	if count > 0:
		center /= count

	return center

# Add new actions for transport operations

func validate_action_with_transport_check(action: Dictionary) -> Dictionary:
	"""Enhanced validation that checks for transport operations"""
	var action_type = action.get("type", "")

	# Check for disembark action
	if action_type == "DISEMBARK_UNIT":
		return _validate_disembark_unit(action)
	elif action_type == "CONFIRM_DISEMBARK":
		return _validate_confirm_disembark(action)

	# For normal movement actions, check if unit is embarked
	var movement_actions = ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK"]
	if action_type in movement_actions:
		var unit_id = action.get("actor_unit_id", "")
		if unit_id != "":
			var unit = get_unit(unit_id)
			if unit and unit.get("embarked_in", null) != null:
				# Redirect to disembark flow
				return {"valid": false, "redirect_to": "DISEMBARK", "unit_id": unit_id}

	# Otherwise use normal validation
	return validate_action(action)

func _validate_disembark_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}

	if unit.get("embarked_in", null) == null:
		return {"valid": false, "errors": ["Unit is not embarked"]}

	var validation = TransportManager.can_disembark(unit_id)
	if not validation.valid:
		return {"valid": false, "errors": [validation.reason]}

	return {"valid": true, "errors": []}

## The per-unit placements a CONFIRM_DISEMBARK carries, keyed by unit id.
## `payload.group_positions` is the 19.03-aware form (bodyguard + attached
## CHARACTERs); `payload.positions` is the legacy bodyguard-only form that AI,
## network and scripted callers still send, so fall back to it.
func _resolve_disembark_group_positions(action: Dictionary) -> Dictionary:
	var unit_id = str(action.get("actor_unit_id", ""))
	var payload = action.get("payload", {})
	var raw = payload.get("group_positions", {})
	var out := {}
	if raw is Dictionary and not raw.is_empty():
		for gid in raw:
			out[str(gid)] = raw[gid]
		# Belt-and-braces: `positions` stays authoritative for the acting unit.
		if payload.get("positions", []).size() > 0:
			out[unit_id] = payload.get("positions", [])
	else:
		out[unit_id] = payload.get("positions", [])
	return out

func _validate_confirm_disembark(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var positions = action.get("payload", {}).get("positions", [])
	var group_positions = _resolve_disembark_group_positions(action)

	if positions.size() == 0:
		return {"valid": false, "errors": ["No positions provided for disembark"]}

	# Validate each position
	var unit = get_unit(unit_id)
	var transport_id = unit.get("embarked_in", null)
	var transport = get_unit(transport_id)

	if not transport:
		return {"valid": false, "errors": ["Transport not found"]}

	# Get transport position for range check
	var transport_pos = _get_unit_center_position(transport_id)
	DebugLogger.info(str("DEBUG MovementPhase: Transport position: ", transport_pos))

	# ISS-058 (11e 18.04): the disembark MODE sets the set-up distance —
	# 3\" for rapid/tactical, 6\" for combat. The template selects the
	# mandatory mode from the transport's move history; the player may
	# signal an impossible tactical set-up via payload.can_setup_tactical.
	var setup_range_inches := 3.0
	var dis_mode := ""
	if GameConstants.edition >= 11:
		var dis_tmpl = MoveTypes.get_type("disembark")
		var dis_el = dis_tmpl.eligible(unit_id, GameState.state)
		if not dis_el.eligible:
			return {"valid": false, "errors": dis_el.reasons}
		var dis_sel = dis_tmpl.select_mode(unit_id, GameState.state,
			{"can_setup_tactical": action.get("payload", {}).get("can_setup_tactical", true)})
		dis_mode = dis_sel.mode
		setup_range_inches = dis_tmpl.setup_distance_inches({"mode": dis_sel.mode})
		log_phase_message("[11e] Disembark mode for %s: %s (set-up %0.0f\")" % [unit_id, dis_sel.mode, setup_range_inches])

	# 19.03: validate every member of the attached unit, not just the bodyguard.
	# `final_models` collects them all so coherency and overlap are measured over
	# the unit as a whole (a leader 2" from the nearest Boy IS coherent).
	var final_models = []
	for gid in group_positions:
		var g_unit = get_unit(str(gid))
		if g_unit.is_empty():
			return {"valid": false, "errors": ["Disembarking unit not found: %s" % str(gid)]}
		var g_positions = group_positions[gid]
		var g_alive_count := 0
		for mi in range(g_unit.models.size()):
			if g_unit.models[mi].get("alive", true):
				g_alive_count += 1
		# Model-indexed or alive-order — TransportManager resolves the shape, and
		# the same map drives the apply step so validation and application can
		# never disagree about which model goes where.
		var g_aligned = TransportManager.align_disembark_positions(g_unit, g_positions)
		if g_aligned.size() < g_alive_count:
			return {"valid": false, "errors": ["Disembark needs a position for every model in %s (%d of %d placed)" % [
				str(g_unit.get("meta", {}).get("name", gid)), g_aligned.size(), g_alive_count]]}

		for i in g_aligned:
			var pos = g_aligned[i]
			DebugLogger.info(str("DEBUG MovementPhase: Model position: ", pos))

			# P3-95: Use centralized shape-aware distance check from TransportManager
			var pos_vec = pos
			if pos is Array:
				pos_vec = Vector2(pos[0], pos[1])
			elif pos is Dictionary:
				pos_vec = Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))
			var range_result = TransportManager.is_position_within_disembark_range(pos_vec, g_unit.models[i], transport, setup_range_inches)
			DebugLogger.info(str("DEBUG MovementPhase: Edge-to-edge distance (inches): ", range_result.distance_inches))
			# Codex: Space Marines (11e) AGGRESSIVE DISEMBARKATION (SMCodex11e.gd): WITHIN (not wholly within) the set-up distance.
			if not range_result.within_range and _sm11e_codex().disembark_range_ok(unit_id, range_result, setup_range_inches):
				DebugLogger.info("MovementPhase: Aggressive Disembarkation — %s model %d set up within (not wholly within) %.0f\" of the transport" % [str(gid), int(i), setup_range_inches])
				range_result["within_range"] = true

			if not range_result.within_range:
				# 18.04 / 18.06: each model is set up WHOLLY within the set-up distance.
				return {"valid": false, "errors": ["Model must be set up wholly within %0.0f\" of transport (its base reaches %.1f\" from the hull)" % [setup_range_inches, float(range_result.get("farthest_inches", range_result.distance_inches))]]}

			# Build model_at_pos for engagement range and board edge checks
			var model_at_pos = g_unit.models[i].duplicate()
			model_at_pos["position"] = pos

			# Check engagement range using shape-aware distance.
			# 18.04 Combat Disembark: each model CAN be set up engaged, but only
			# with enemy units the TRANSPORT itself is engaged with.
			if GameConstants.edition >= 11 and dis_mode == "combat":
				for engaged_enemy_id in _model_engaged_enemy_ids(model_at_pos, g_unit.owner):
					var engaged_enemy = game_state_snapshot.units[engaged_enemy_id]
					if not RulesEngine.check_units_in_engagement_range(transport, engaged_enemy, game_state_snapshot):
						return {"valid": false, "errors": ["Combat Disembark: models may only be set up engaged with enemy units the transport is engaged with (18.04); %s is not engaged with the transport" % engaged_enemy_id]}
			elif _model_in_engagement_range(model_at_pos, g_unit.owner):
				return {"valid": false, "errors": ["Cannot disembark within Engagement Range of enemy"]}

			# Check board edge - no part of model base can extend beyond the battlefield
			if _position_outside_board_bounds(pos_vec, model_at_pos):
				return {"valid": false, "errors": ["Cannot disembark beyond the board edge"]}

			final_models.append(model_at_pos)

	# Check unit coherency: disembarked models must maintain 2" horizontal and 5" vertical coherency
	var coherency_result = _check_models_coherency(final_models)
	if not coherency_result.valid:
		return {"valid": false, "errors": coherency_result.errors}

	# Models cannot be set up overlapping other models (their own placements
	# are checked pairwise, plus every other on-board model). The placement UI
	# already enforces this — this keeps engine-only paths (AI / network /
	# scripted actions) honest too.
	for i in range(final_models.size()):
		for j in range(i + 1, final_models.size()):
			if Measurement.models_overlap(final_models[i], final_models[j]):
				return {"valid": false, "errors": ["Disembark positions overlap each other"]}
	for other_id in game_state_snapshot.units:
		if other_id in group_positions:
			continue
		var other_unit = game_state_snapshot.units[other_id]
		if other_unit.get("embarked_in", null) != null:
			continue
		for other_model in other_unit.get("models", []):
			if not other_model.get("alive", true) or other_model.get("position") == null:
				continue
			for placed in final_models:
				if Measurement.models_overlap(placed, other_model):
					return {"valid": false, "errors": ["Disembark position overlaps a model from %s" % other_id]}
	# WP-M4a DROP POD ASSAULT: units disembarking as the Drop Pod lands are set up more than 8" from enemy units.
	for dp_gid in group_positions:
		var dp_err: Array = _sm11e_abilities_a().disembark_setup_errors(str(dp_gid), TransportManager.align_disembark_positions(get_unit(str(dp_gid)), group_positions[dp_gid]))
		if not dp_err.is_empty():
			return {"valid": false, "errors": dp_err}

	return {"valid": true, "errors": []}

func _model_in_engagement_range(model_data: Dictionary, owner: int) -> bool:
	"""Check if a model is within engagement range of any enemy model (shape-aware)"""
	var enemy_player = 3 - owner
	for enemy_id in game_state_snapshot.units:
		var enemy = game_state_snapshot.units[enemy_id]
		if enemy.owner != enemy_player:
			continue

		# Skip embarked enemies
		if enemy.get("embarked_in", null) != null:
			continue

		for model in enemy.models:
			if not model.alive or model.position == null:
				continue

			# T3-9: Use barricade-aware engagement range (2" through barricades)
			var model_pos = model_data.get("position", Vector2.ZERO)
			if model_pos is Dictionary:
				model_pos = Vector2(model_pos.get("x", 0), model_pos.get("y", 0))
			var enemy_pos = model.get("position", Vector2.ZERO)
			if enemy_pos is Dictionary:
				enemy_pos = Vector2(enemy_pos.get("x", 0), enemy_pos.get("y", 0))
			var effective_er = _get_effective_engagement_range(model_pos, enemy_pos)
			if Measurement.is_in_engagement_range_shape_aware(model_data, model, effective_er):
				return true

	return false

func _model_engaged_enemy_ids(model_data: Dictionary, owner: int) -> Array:
	"""Enemy unit ids with at least one model in engagement range of this
	model (shape-aware) — used by the 18.04 Combat Disembark exception."""
	var out: Array = []
	var enemy_player = 3 - owner
	for enemy_id in game_state_snapshot.units:
		var enemy = game_state_snapshot.units[enemy_id]
		if enemy.owner != enemy_player:
			continue
		if enemy.get("embarked_in", null) != null:
			continue
		for model in enemy.models:
			if not model.alive or model.position == null:
				continue
			var model_pos = model_data.get("position", Vector2.ZERO)
			if model_pos is Dictionary:
				model_pos = Vector2(model_pos.get("x", 0), model_pos.get("y", 0))
			var enemy_pos = model.get("position", Vector2.ZERO)
			if enemy_pos is Dictionary:
				enemy_pos = Vector2(enemy_pos.get("x", 0), enemy_pos.get("y", 0))
			var effective_er = _get_effective_engagement_range(model_pos, enemy_pos)
			if Measurement.is_in_engagement_range_shape_aware(model_data, model, effective_er):
				out.append(enemy_id)
				break
	return out

func _position_in_engagement_range(pos: Vector2, owner: int) -> bool:
	"""Check if a position is within engagement range of any enemy model"""
	var enemy_player = 3 - owner
	for enemy_id in game_state_snapshot.units:
		var enemy = game_state_snapshot.units[enemy_id]
		if enemy.owner != enemy_player:
			continue

		# Skip embarked enemies
		if enemy.get("embarked_in", null) != null:
			continue

		for model in enemy.models:
			if not model.alive or model.position == null:
				continue

			var model_pos = Vector2(model.position.x, model.position.y)
			if Measurement.distance_inches(pos, model_pos) <= 1.0:
				return true

	return false

# Disembark action handlers

func _process_disembark_unit(action: Dictionary) -> Dictionary:
	"""Start the disembark process by showing dialog"""
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)

	# Check if unit can disembark
	var validation = TransportManager.can_disembark(unit_id)
	if not validation.valid:
		return create_result(false, [], validation.reason)

	# Codex: Space Marines (11e) AGGRESSIVE DISEMBARKATION (SMCodex11e.gd): "when a
	# friendly ADEPTUS ASTARTES unit embarked within a TRANSPORT is selected to
	# move" — the owner's unit_selected_to_move window (move_type "disembark")
	# opens first, only when that player has such a stratagem.
	if GameConstants.edition >= 11 and _sm11e_codex().player_has_window_stratagem(int(unit.get("owner", 0)), "unit_selected_to_move"):
		var dis_stm := _ork11e_open_selected_to_move_windows(action, "disembark")
		if dis_stm.paused:
			return create_result(true, dis_stm.diffs)
		return _ork11e_merge_diffs(_process_disembark_unit_after_windows(action), dis_stm.diffs)
	return _process_disembark_unit_after_windows(action)

## The disembark once the unit_selected_to_move window (if any) has closed.
func _process_disembark_unit_after_windows(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)

	# Show disembark dialog
	call_deferred("_show_disembark_dialog", unit_id)

	log_phase_message("Starting disembark for %s" % unit.meta.get("name", unit_id))
	return create_result(true, [])

func _show_disembark_dialog(unit_id: String) -> void:
	"""Show disembark confirmation dialog"""
	var dialog = preload("res://scripts/DisembarkDialog.gd").new()
	dialog.setup(unit_id)
	dialog.disembark_confirmed.connect(_on_disembark_confirmed.bind(unit_id))
	dialog.disembark_canceled.connect(_on_disembark_canceled.bind(unit_id))
	get_tree().root.add_child(dialog)
	DialogUtils.popup_at_bottom(dialog)

func _on_disembark_confirmed(combat_mode: bool, unit_id: String) -> void:
	"""Handle disembark confirmation - start placement.
	Signature note: disembark_confirmed emits (combat_mode) and unit_id is
	bound at connect time — a 1-arg handler here fails the signal call."""
	var controller = preload("res://scripts/DisembarkController.gd").new()
	# 11e 18.04: the dialog's Combat Disembark toggle switches the placement
	# rules (6" set-up, engaged-with-transport's-foes allowed) and is echoed
	# to CONFIRM_DISEMBARK via payload.can_setup_tactical=false.
	controller.combat_requested = combat_mode
	_pending_combat_disembark[unit_id] = combat_mode
	controller.disembark_completed.connect(_on_disembark_placement_completed)
	controller.disembark_canceled.connect(_on_disembark_placement_canceled)
	get_tree().root.add_child(controller)
	controller.start_disembark(unit_id)

func _on_disembark_canceled(unit_id: String) -> void:
	"""Handle disembark cancellation"""
	log_phase_message("Disembark cancelled for %s" % get_unit(unit_id).meta.get("name", unit_id))

func _on_disembark_placement_completed(unit_id: String, positions: Array, group_positions: Dictionary = {}) -> void:
	"""Handle completed disembark placement - routes through CONFIRM_DISEMBARK action"""
	var action = {
		"type": "CONFIRM_DISEMBARK",
		"actor_unit_id": unit_id,
		"payload": {
			"positions": positions,
			# 19.03: every member of the attached unit's placements, so attached
			# CHARACTERs leave the transport with their squad.
			"group_positions": group_positions,
			"can_setup_tactical": not _pending_combat_disembark.get(unit_id, false)
		}
	}
	_pending_combat_disembark.erase(unit_id)
	# execute_action (not process_action): the returned changes — the 11e
	# after-move flags (disembarked_this_turn, cannot_charge, battle_shocked)
	# — are only applied by execute_action, matching the controller path.
	var result = execute_action(action)

	if not result.get("success", false):
		log_phase_message("Disembark failed: %s" % result.get("error", "Unknown error"))
		return

func _initialize_movement_for_disembarked_unit(unit_id: String) -> void:
	"""Initialize movement state for a unit that just disembarked"""
	log_phase_message("Initializing movement for disembarked unit: %s" % unit_id)
	var unit = get_unit(unit_id)
	var move_inches = get_unit_movement(unit)

	log_phase_message("Setting up active_moves for %s with %d\" movement" % [unit_id, move_inches])

	# Set up active movement similar to BEGIN_NORMAL_MOVE
	active_moves[unit_id] = {
		"mode": "NORMAL",
		# 18.04: after a tactical disembark the unit "is then selected to make a
		# normal OR advance move" — so default to Normal but leave the mode
		# decision OPEN (not locked). Locking to Normal here hid the Advance
		# option from BOTH the mouse mode radios and the pad move menu (the
		# PadActionBar), even though the transport hadn't moved and the unit was
		# fully eligible to Advance. Unlocking lets the player pick Advance the
		# same way they would for any other move; switching to Advance recreates
		# active_moves via BEGIN_ADVANCE (rolling the D6), so the default Normal
		# state here is only the starting point.
		"mode_locked": false,
		"completed": false,
		"move_cap_inches": move_inches,
		"advance_roll": 0,
		"model_moves": [],
		"staged_moves": [],
		"original_positions": {},
		"original_rotations": {},
		"model_distances": {},
		"dice_rolls": [],
		"group_moves": [],
		"group_selection": [],
		"group_formation": {},
		"accumulated_distance": 0.0  # Track distance moved
	}

	# Store original positions for reset capability (composite keys for consistency)
	log_phase_message("Storing original positions for %s models" % unit_id)
	for i in range(unit.models.size()):
		var model = unit.models[i]
		if model.alive and model.position:
			var pos = Vector2(model.position.x, model.position.y)
			var model_key = "%s:%s" % [unit_id, model.id]
			active_moves[unit_id]["original_positions"][model_key] = pos
			active_moves[unit_id]["model_distances"][model_key] = 0.0
			log_phase_message("  Model %s original position: %s" % [model.id, pos])

	# Apply movement capability state changes
	var changes = [
		{
			"op": "set",
			"path": "units.%s.flags.move_cap_inches" % unit_id,
			"value": move_inches
		},
		{
			"op": "set",
			"path": "units.%s.flags.movement_active" % unit_id,
			"value": true
		}
	]

	# Apply through parent if it exists (PhaseManager)
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)

	# Update our local copy of the state
	var local_unit = game_state_snapshot.units[unit_id]
	if not local_unit.has("flags"):
		local_unit["flags"] = {}
	local_unit.flags["move_cap_inches"] = move_inches
	local_unit.flags["movement_active"] = true

	log_phase_message("Active moves successfully set up for %s. Total active moves: %s" % [unit_id, active_moves.keys()])

	emit_signal("unit_move_begun", unit_id, "NORMAL")
	log_phase_message("Movement initialized for disembarked unit %s (M: %d\")" % [unit.meta.get("name", unit_id), move_inches])

func _on_disembark_placement_canceled(unit_id: String) -> void:
	"""Handle cancelled disembark placement"""
	log_phase_message("Disembark placement cancelled for %s" % get_unit(unit_id).meta.get("name", unit_id))

func _on_transport_manager_disembark_completed(_unit_id: String) -> void:
	"""Legacy signal handler — disembark is now handled entirely by CONFIRM_DISEMBARK action.
	Kept as a no-op safety net; all logic lives in _process_confirm_disembark()."""
	pass

## Positions for an attached CHARACTER whose disembark payload carries none —
## the AI, network and scripted callers only ever build the bodyguard's array.
## Rings out from the already-placed models, keeping each base within the set-up
## distance of the transport, in coherency (2") with a placed model, clear of
## every other base, outside Engagement Range and on the board. Returns [] when
## no legal spot exists, which fails validation rather than dropping the leader.
func _auto_disembark_positions(char_unit: Dictionary, transport: Dictionary, placed_models: Array, setup_range_inches: float) -> Array:
	var out: Array = []
	var anchors: Array = placed_models.duplicate()
	var coherency_px := Measurement.inches_to_px(2.0)

	for mi in range(char_unit.get("models", []).size()):
		var model = char_unit.models[mi]
		if not model.get("alive", true):
			continue

		var found: Vector2 = Vector2.INF
		var radius_px := Measurement.base_radius_px(int(model.get("base_mm", 32)))
		# Search outward from each already-placed model so the leader lands beside
		# the squad it leads rather than at some arbitrary point on the ring.
		for anchor in anchors:
			var a_pos = anchor.get("position", null)
			if a_pos == null:
				continue
			var anchor_vec := Vector2(float(a_pos.get("x", 0)), float(a_pos.get("y", 0))) if a_pos is Dictionary else Vector2(a_pos.x, a_pos.y)
			var anchor_radius_px := Measurement.base_radius_px(int(anchor.get("base_mm", 32)))
			for ring in range(6):
				var dist := anchor_radius_px + radius_px + 2.0 + ring * (radius_px * 0.5)
				for step in range(24):
					var angle := (float(step) / 24.0) * TAU
					var candidate := anchor_vec + Vector2(cos(angle), sin(angle)) * dist
					var test_model = model.duplicate()
					test_model["position"] = {"x": candidate.x, "y": candidate.y}

					if not TransportManager.is_position_within_disembark_range(candidate, model, transport, setup_range_inches).within_range:
						continue
					if _position_outside_board_bounds(candidate, test_model):
						continue
					if _model_in_engagement_range(test_model, int(char_unit.get("owner", 1))):
						continue

					var overlaps := false
					for other in anchors:
						if Measurement.models_overlap(test_model, other):
							overlaps = true
							break
					if overlaps:
						continue
					for other_id in game_state_snapshot.units:
						var other_unit = game_state_snapshot.units[other_id]
						if other_unit.get("embarked_in", null) != null:
							continue
						for other_model in other_unit.get("models", []):
							if not other_model.get("alive", true) or other_model.get("position") == null:
								continue
							if Measurement.models_overlap(test_model, other_model):
								overlaps = true
								break
						if overlaps:
							break
					if overlaps:
						continue

					# Must be in coherency with something already placed.
					var coherent := false
					for other in anchors:
						if Measurement.model_to_model_distance_px(test_model, other) <= coherency_px:
							coherent = true
							break
					if not coherent:
						continue

					found = candidate
					break
				if found != Vector2.INF:
					break
			if found != Vector2.INF:
				break

		if found == Vector2.INF:
			log_phase_message("WARNING: no legal auto-disembark position for %s model %d" % [str(char_unit.get("meta", {}).get("name", "?")), mi])
			return []

		out.append({"x": found.x, "y": found.y})
		var placed = model.duplicate()
		placed["position"] = {"x": found.x, "y": found.y}
		anchors.append(placed)

	return out

## Fill in placements for any attached CHARACTER the caller did not place, so an
## engine-side disembark (AI, network, scripted action) never strands a leader
## inside the transport. Returns the action with a complete `group_positions`.
func _complete_disembark_group_payload(action: Dictionary) -> Dictionary:
	var unit_id = str(action.get("actor_unit_id", ""))
	var group_positions = _resolve_disembark_group_positions(action)
	var group = TransportManager.get_disembark_group(unit_id, game_state_snapshot)
	var missing := []
	for gid in group:
		if not group_positions.has(gid) or group_positions[gid].size() == 0:
			missing.append(gid)
	if missing.is_empty():
		var filled = action.duplicate(true)
		filled["payload"] = action.get("payload", {}).duplicate(true)
		filled["payload"]["group_positions"] = group_positions
		return filled

	var unit = get_unit(unit_id)
	var transport = get_unit(str(unit.get("embarked_in", "")))
	var setup_range_inches := 3.0
	if GameConstants.edition >= 11:
		var dis_tmpl = MoveTypes.get_type("disembark")
		var dis_sel = dis_tmpl.select_mode(unit_id, GameState.state,
			{"can_setup_tactical": action.get("payload", {}).get("can_setup_tactical", true)})
		setup_range_inches = dis_tmpl.setup_distance_inches({"mode": dis_sel.mode})

	# Anchors: every model already placed by this disembark.
	var placed_models: Array = []
	for gid in group_positions:
		var g_unit = get_unit(str(gid))
		var pi := 0
		for mi in range(g_unit.get("models", []).size()):
			if not g_unit.models[mi].get("alive", true):
				continue
			if pi >= group_positions[gid].size():
				break
			var m = g_unit.models[mi].duplicate()
			m["position"] = group_positions[gid][pi]
			placed_models.append(m)
			pi += 1

	for gid in missing:
		var char_unit = get_unit(gid)
		var auto_positions = _auto_disembark_positions(char_unit, transport, placed_models, setup_range_inches)
		log_phase_message("Auto-placed %d model(s) for attached character %s disembarking with %s" % [
			auto_positions.size(), gid, unit_id])
		group_positions[gid] = auto_positions
		var api := 0
		for mi in range(char_unit.get("models", []).size()):
			if not char_unit.models[mi].get("alive", true):
				continue
			if api >= auto_positions.size():
				break
			var m = char_unit.models[mi].duplicate()
			m["position"] = auto_positions[api]
			placed_models.append(m)
			api += 1

	var out = action.duplicate(true)
	out["payload"] = action.get("payload", {}).duplicate(true)
	out["payload"]["group_positions"] = group_positions
	return out

func _process_confirm_disembark(action: Dictionary) -> Dictionary:
	"""Process confirmation of disembark positions — single authoritative disembark path"""
	var unit_id = action.get("actor_unit_id", "")

	# 19.03: an attached unit disembarks as ONE unit. Fill in any attached
	# CHARACTER the caller did not place, then validate the complete set.
	action = _complete_disembark_group_payload(action)
	var group_positions = action.get("payload", {}).get("group_positions", {})
	var positions = action.get("payload", {}).get("positions", [])

	# Validate positions
	var validation = _validate_confirm_disembark(action)
	if not validation.valid:
		return create_result(false, [], validation.errors[0])

	# ISS-058 (11e 18.04): resolve the mode before the move executes —
	# combat disembark rolls a hazard per model BEFORE moving.
	var dis_mode := ""
	var dis_changes: Array = []
	if GameConstants.edition >= 11:
		var dis_tmpl = MoveTypes.get_type("disembark")
		var dis_sel = dis_tmpl.select_mode(unit_id, GameState.state,
			{"can_setup_tactical": action.get("payload", {}).get("can_setup_tactical", true)})
		dis_mode = str(dis_sel.mode)
		# 19.03: the hazard roll and the after-move flags apply to the whole
		# attached unit — the leader takes the same risk and the same
		# battle-shocked / cannot-charge consequences as the squad it rides with.
		for gid in group_positions:
			if dis_mode == "combat":
				var unit_pre = GameState.get_unit(str(gid))
				var ctx = dis_tmpl.before_moving(str(gid), GameState.state, RulesEngine.make_rng(), {"mode": "combat"})
				var hz = ctx.get("hazard", {})
				log_phase_message("[11e] Combat disembark hazards for %s: %s (%d failure(s))" % [str(gid), str(hz.get("rolls", [])), int(hz.get("failures", 0))])
				if int(hz.get("failures", 0)) > 0:
					# Feel No Pain vs mortal wounds (incl. Aegis of the Emperor, WP-C3).
					var dis_mw: int = RulesEngine.mortal_wounds_after_fnp(unit_pre, int(hz.get("mortal_wounds", 0)), null, [], false, "combat_disembark")
					var mw_out = Allocation.apply_mortal_wounds_11e(unit_pre, dis_mw, CasualtyPreference.engine_auto_preference(unit_pre, GameState.state))
					for ridx in mw_out.remaining:
						dis_changes.append({"op": "set", "path": "units.%s.models.%d.current_wounds" % [str(gid), int(ridx)], "value": int(mw_out.remaining[ridx])})
					for di in mw_out.models_destroyed:
						dis_changes.append({"op": "set", "path": "units.%s.models.%d.alive" % [str(gid), int(di)], "value": false})
			dis_changes.append_array(dis_tmpl.after_moving_effects(str(gid), {"mode": dis_mode}))

	# WP-O6: the hull the unit leaves (Idol of Belligerence / Beastscent below).
	var o6_transport_id := str(GameState.get_unit(unit_id).get("embarked_in", ""))
	if o6_transport_id == "<null>":
		o6_transport_id = ""

	# Execute disembark through TransportManager (single call site per unit —
	# the bodyguard and every attached CHARACTER leave the hull together).
	for gid in group_positions:
		var g_positions = group_positions[gid]
		TransportManager.disembark_unit(str(gid), g_positions)
		if str(gid) != unit_id:
			log_phase_message("Attached character %s disembarked with %s (%d model(s))" % [str(gid), unit_id, g_positions.size()])

	# Refresh local snapshot so subsequent logic sees the updated state
	game_state_snapshot = GameState.state.duplicate(true)
	log_phase_message("Refreshed game state snapshot after disembark")

	var unit = get_unit(unit_id)
	log_phase_message("Unit %s disembarked via CONFIRM_DISEMBARK action" % unit.meta.get("name", unit_id))

	# WP-O6: Codex: Orks (11e) disembark triggers — IDOL OF BELLIGERENCE
	# (Stompa: disembarking units are riled up) and BEASTSCENT (Kill Rig).
	if GameConstants.edition >= 11 and o6_transport_id != "":
		dis_changes.append_array(_cus11e_abilities().on_disembark(unit_id, o6_transport_id, dis_mode))  # WP-C7 Assault Dropship
		var o6_dis: Array = OrkAbilities11eScript.on_disembark(unit_id, o6_transport_id)
		if not o6_dis.is_empty():
			dis_changes.append_array(o6_dis)
			game_state_snapshot = GameState.state.duplicate(true)

	if GameConstants.edition >= 11:
		# 18.04 AFTER per mode: tactical = the unit is then SELECTED to
		# make a normal or advance move; rapid/combat lock further moves.
		# If the transport already moved this turn the disembarked unit
		# cannot move (TransportManager.disembark_unit sets cannot_move) —
		# do NOT hand it a post-disembark move in that case.
		if dis_mode == "tactical" and not unit.get("flags", {}).get("cannot_move", false):
			log_phase_message("[11e] Tactical disembark — %s is selected for a normal/advance move" % unit_id)
			call_deferred("_initialize_movement_for_disembarked_unit", unit_id)
		elif dis_mode == "tactical":
			log_phase_message("[11e] Tactical disembark — %s cannot move (transport moved this turn)" % unit_id)
		if dis_mode == "assault":
			log_phase_message("[11e] Assault disembark (18.06) — %s set up within 3\" of the transport; still eligible to charge" % unit_id)
		# Codex: Orks (11e) READIED BRAWLERS: continue / finish the follow-up.
		var dis_result := _ork11e_after_assault_disembark(unit_id, dis_changes)
		# Codex: Orks (11e) enemy_ended_move: a disembark move is a move (18.04),
		# so the opponent's window opens once it has ended (a tactical
		# disembark's follow-up normal/advance move opens its own). Not for an
		# assault disembark run inside a stratagem follow-up (READIED BRAWLERS):
		# that window flow is still in progress.
		if dis_mode != "assault" and not _window_followup_pending:
			_ork11e_eem_pending = {"unit_id": unit_id, "move_type": "disembark"}
			_ork11e_pending_move_changes = []
			return _ork11e_with_enemy_ended_move(dis_result)
		return dis_result
	# Post-disembark: offer movement if the transport hadn't already moved
	if unit and not unit.get("flags", {}).get("cannot_move", false):
		log_phase_message("Unit %s can move after disembark" % unit.meta.get("name", unit_id))
		call_deferred("_initialize_movement_for_disembarked_unit", unit_id)
	else:
		log_phase_message("Unit %s cannot move after disembark (transport moved)" % unit.meta.get("name", unit_id))

	return create_result(true, [])

# Embark action handlers

func _validate_embark_unit(action: Dictionary) -> Dictionary:
	"""Validate that a unit can embark into a transport during the movement phase"""
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}

	var transport_id = action.get("payload", {}).get("transport_id", "")
	if transport_id == "":
		return {"valid": false, "errors": ["Missing transport_id in payload"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}

	# Unit must belong to the current player
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Unit must have moved this phase (embark happens after movement)
	if not unit.get("flags", {}).get("moved", false):
		return {"valid": false, "errors": ["Unit must complete movement before embarking"]}

	# Units that disembarked this phase cannot re-embark
	if unit.get("disembarked_this_phase", false):
		return {"valid": false, "errors": ["Unit disembarked this phase and cannot re-embark"]}

	# Delegate capacity/keyword checks to TransportManager
	var can_embark = TransportManager.can_embark(unit_id, transport_id)
	if not can_embark.valid:
		return {"valid": false, "errors": [can_embark.reason]}

	return {"valid": true, "errors": []}

func _process_embark_unit(action: Dictionary) -> Dictionary:
	"""Process embarking a unit into a transport via the action system"""
	var unit_id = action.get("actor_unit_id", "")
	var transport_id = action.get("payload", {}).get("transport_id", "")

	var unit = get_unit(unit_id)
	var transport = get_unit(transport_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var transport_name = transport.get("meta", {}).get("name", transport_id)

	# Build state changes following the same pattern as DeploymentPhase embark
	var changes = []
	var current_embarked = transport.get("transport_data", {}).get("embarked_units", []).duplicate()

	# 19.03: an attached unit — bodyguard plus every CHARACTER attached to it —
	# boards as a single unit. Embarking only the bodyguard stranded the leader
	# on the battlefield with the unit it belongs to inside the hull.
	for gid in TransportManager.get_attached_unit_group(unit_id, game_state_snapshot):
		changes.append({
			"op": "set",
			"path": "units.%s.embarked_in" % gid,
			"value": transport_id
		})
		# 18.04 / 18.06 ELIGIBLE IF "did not embark within that TRANSPORT this
		# phase" (DisembarkMove.eligible, READIED BRAWLERS' assault-disembark
		# candidates). Cleared by PhaseManager when the phase ends.
		changes.append({
			"op": "set",
			"path": "units.%s.flags.embarked_this_phase" % gid,
			"value": true
		})

		if gid not in current_embarked:
			current_embarked.append(gid)

		# Embarked models are off the battlefield: clear their positions. Leaving
		# the old positions in place made embarked units targetable by shooting,
		# count as "on the battlefield" for charges, and block placement (they kept
		# phantom footprints at their pre-embark spots).
		var g_models = get_unit(gid).get("models", [])
		for i in range(g_models.size()):
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [gid, i],
				"value": null
			})

		if gid != unit_id:
			log_phase_message("Attached character %s embarked with %s" % [gid, unit_name])

	# Update transport's embarked_units list
	changes.append({
		"op": "set",
		"path": "units.%s.transport_data.embarked_units" % transport_id,
		"value": current_embarked
	})

	log_phase_message("Unit %s embarked in transport %s" % [unit_name, transport_name])

	return create_result(true, changes)

func _build_final_occupancy(pending_changes: Array) -> Dictionary:
	# Map "unit_id:model_id" -> a copy of the model carrying its FINAL position for
	# this move. Live GameState position is overridden by any pending position
	# set-op (bodyguard drops + explicitly-staged character moves not yet applied).
	var pending_pos := {}
	for ch in pending_changes:
		if not (ch is Dictionary):
			continue
		if ch.get("op") != "set":
			continue
		var p_path := str(ch.get("path", ""))
		if p_path.ends_with(".position"):
			pending_pos[p_path] = ch.get("value")
	var occ := {}
	var units = game_state_snapshot.get("units", {})
	for uid in units:
		var models = units[uid].get("models", [])
		for i in range(models.size()):
			var m = models[i]
			if not m.get("alive", true):
				continue
			var mid = m.get("id", "m%d" % (i + 1))
			var m_path := "units.%s.models.%d.position" % [uid, i]
			var pos_val = pending_pos.get(m_path, m.get("position"))
			if pos_val == null:
				continue
			var mcopy = m.duplicate(true)
			mcopy["position"] = pos_val
			occ["%s:%s" % [uid, mid]] = mcopy
	return occ

func _occupancy_values_excluding(occupancy: Dictionary, exclude_key: String) -> Array:
	var out := []
	for k in occupancy:
		if k == exclude_key:
			continue
		out.append(occupancy[k])
	return out

func _move_attached_characters(bodyguard_id: String, attached_char_ids: Array, explicitly_moved_models: Dictionary = {}, pending_changes: Array = []) -> Array:
	"""Move attached character models to maintain formation with bodyguard.
	Calculates delta from the bodyguard's first model move and applies to character models.
	Models in explicitly_moved_models were already positioned via staged moves and are skipped.
	pending_changes holds the position set-ops built earlier this confirm (bodyguard
	final positions + explicitly-staged character positions) so the rigidly-translated
	character models can be nudged off any model they would land on."""
	var changes = []
	var bodyguard = get_unit(bodyguard_id)
	if bodyguard.is_empty():
		return changes

	# Calculate movement delta from first bodyguard model (only from bodyguard models, not character models)
	var bg_models = bodyguard.get("models", [])
	var bg_model_ids = {}
	for bg_m in bg_models:
		bg_model_ids[bg_m.get("id", "")] = true
	var move_delta = Vector2.ZERO
	var found_delta = false

	# Find the movement delta from the active_moves data
	if active_moves.has(bodyguard_id):
		var move_data = active_moves[bodyguard_id]
		for model_move in move_data.model_moves:
			# Only use bodyguard model moves for delta calculation, not character model moves
			if model_move.model_id in bg_model_ids:
				var from_pos = model_move.get("from", null)
				var to_pos = model_move.get("dest", null)
				if from_pos != null and to_pos != null:
					var from_vec = Vector2(from_pos.x if from_pos is Vector2 else from_pos.get("x", 0), from_pos.y if from_pos is Vector2 else from_pos.get("y", 0))
					var to_vec = Vector2(to_pos.x if to_pos is Vector2 else to_pos.get("x", 0), to_pos.y if to_pos is Vector2 else to_pos.get("y", 0))
					move_delta = to_vec - from_vec
					found_delta = true
					break

	if not found_delta:
		DebugLogger.info(str("[MovementPhase] WARNING: Could not determine move delta for attached characters of %s" % bodyguard_id))
		return changes

	DebugLogger.info(str("[MovementPhase] Moving attached characters with delta: %s" % str(move_delta)))

	# Occupancy of every alive model at its FINAL position for this move (pending
	# changes override live state). Keyed by "unit:model_id" so we can exclude the
	# model being placed and fold each resolved character position back in, keeping
	# multiple attached characters from stacking on each other. See fix for the
	# "attached character overlaps its bodyguard after Advance/Charge" bug.
	var occupancy := _build_final_occupancy(pending_changes)

	for char_id in attached_char_ids:
		var char_unit = get_unit(char_id)
		if char_unit.is_empty():
			continue

		var char_models = char_unit.get("models", [])
		for i in range(char_models.size()):
			var model = char_models[i]
			var model_id = model.get("id", "m%d" % (i + 1))

			# Skip models that were already explicitly moved via staged moves
			# Uses unit_id:model_id key to handle model ID collisions (e.g. "m1" in both units)
			var model_key = "%s:%s" % [char_id, model_id]
			if explicitly_moved_models.has(model_key):
				DebugLogger.info(str("[MovementPhase] Skipping attached character model %s — already explicitly moved" % model_id))
				continue

			var model_pos = model.get("position", null)
			if model_pos == null:
				continue

			var pos_x = model_pos.get("x", 0) if model_pos is Dictionary else model_pos.x
			var pos_y = model_pos.get("y", 0) if model_pos is Dictionary else model_pos.y
			var ideal_pos = Vector2(pos_x + move_delta.x, pos_y + move_delta.y)

			# Nudge off any model the rigid delta would land the character on (its
			# own stale spot is excluded so it never blocks itself).
			var others := _occupancy_values_excluding(occupancy, model_key)
			var new_pos = Measurement.find_nearest_non_overlapping_position(model, ideal_pos, others)
			if new_pos != ideal_pos:
				DebugLogger.info(str("[MovementPhase] Attached character %s.%s nudged off overlap: ideal %s -> %s" % [char_id, model_id, str(ideal_pos), str(new_pos)]))

			# Record this character's resolved position so later attached models avoid it too.
			var placed = model.duplicate(true)
			placed["position"] = new_pos
			occupancy[model_key] = placed

			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [char_id, i],
				"value": {"x": new_pos.x, "y": new_pos.y}
			})

		# Also set character unit flags to match bodyguard
		changes.append({
			"op": "set",
			"path": "units.%s.flags.moved" % char_id,
			"value": true
		})

		var char_name = char_unit.get("meta", {}).get("name", char_id)
		DebugLogger.info(str("[MovementPhase] Moved attached character %s with bodyguard %s" % [char_name, bodyguard_id]))

	return changes

# ============================================================================
# STRATAGEM HANDLING (active stratagems with phase: "movement")
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
	DebugLogger.info(str("MovementPhase: Stratagem %s used (target=%s)" % [strat_name, target_unit_id]))
	return create_result(true, result.get("diffs", []), "Used " + strat_name)
