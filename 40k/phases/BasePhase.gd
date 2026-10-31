extends Node
class_name BasePhase

const GameStateData = preload("res://autoloads/GameState.gd")


# BasePhase - Abstract base class for all game phases
# Defines the standard interface that all phases must implement

signal phase_completed()
signal action_taken(action: Dictionary)
# T09 (design doc §8, exhaustion shading): fires the moment a unit's
# has_unit_acted_this_phase() answer flips to true — it finished its move,
# shot, charged or fought. UnitExhaustionTracker dims that unit's board tokens
# and roster card until the phase ends.
signal unit_acted_in_phase(unit_id: String)

# ============================================================================
# STRATAGEM WINDOWS (design .llm/ork_codex_11e_design.md §3.1, §3.2, §6)
# ============================================================================
# A phase OPENS a window at a hook point (open_stratagem_window). The window
# computes offers for one decider (StratagemManager.get_window_offers) and
#  - resolves synchronously when there are no offers or the decider is an AI
#    (AIDecisionMaker.decide_window_stratagem) -> returns false, caller goes on;
#  - otherwise PAUSES the phase: stratagem_window_opened fires (Main shows the
#    StratagemDialog on the decider's seat), every action except
#    USE_WINDOW_STRATAGEM / DECLINE_WINDOW_STRATAGEM is rejected, and when the
#    queue drains the phase's resume_method(ctx, window_result) continues the
#    interrupted flow -> returns true.
signal stratagem_window_opened(player: int, window_id: String, offers: Array, ctx: Dictionary)
signal stratagem_window_closed(player: int, window_id: String, used: bool)

const WINDOW_ACTION_TYPES: Array = ["USE_WINDOW_STRATAGEM", "DECLINE_WINDOW_STRATAGEM"]

var _window_queue: Array = []            # [{player, window_id, ctx}] still to open
var _window_pending: Dictionary = {}     # {player, window_id, offers, ctx} while a human decides
var _window_resume_method: String = ""   # phase method called when the queue drains
var _window_resume_ctx: Dictionary = {}  # ctx handed to the resume method
var _window_suppressed: Dictionary = {}  # "player:window_id" -> true ("Don't offer again this phase")
var _window_sync_diffs: Array = []       # diffs applied by synchronous (AI) uses — merged into the caller's result
var _window_followup_pending: bool = false  # a used stratagem's follow-up paused the phase
var _window_last_result: Dictionary = {}  # {used, player, window_id, stratagem_id, target_unit_id, diffs}
# Extra result keys a follow-up produced (FIRE OVERWATCH's snap-shooting dice /
# summary): merged into the result of the action that answered the window
# (_process_window_action) — or opened it, when an AI decided synchronously.
var _window_result_extra: Dictionary = {}

# Cross-phase EVENT windows (unit_battle_shocked, unit_destroyed,
# enemy_unit_has_attacked — design §3): raised by comparing unit state before
# and after each action, queued in _ev_deferred and opened as soon as nothing
# else is pending (end of the action, or when the current window closes).
var _ev_baseline: Dictionary = {}        # {"alive": {uid: true}, "shocked": {uid: true}} at the last detection
var _ev_deferred: Array = []             # [{player, window_id, ctx}] raised by events, not yet opened
var _ev_attacks: Dictionary = {}         # attacker_unit_id -> Array of enemy unit ids destroyed during its attacks
var _ev_destroyed_open: Dictionary = {}  # unit_id -> true while its unit_destroyed window is queued/open
var _ev_dd_held: Dictionary = {}         # unit_id -> true: Deadly Demise waits for its unit_destroyed window
var _ev_dd_released: Array = []          # unit ids whose held Deadly Demise was resolved (log / tests)
var _ev_action_attacker: String = ""     # unit making attacks in the action being executed
var _ev_destroyed_by: Dictionary = {}    # unit_id -> attacker whose attacks destroyed it earlier (removal deferred, e.g. Fight On Death); consumed by the next detection
var _ev_depth: int = 0                   # execute_action nesting (events are flushed at depth 0)

# ISS-024: phases read LIVE state — this is a property view over
# GameState.state, so phase code can never act on stale data and the
# old hand-patching sites become idempotent writes of live values.
# Assignments (enter_phase, legacy refresh sites) are no-ops. Where a
# frozen view is semantically required (e.g. "models in the target unit
# at Select Targets"), take an explicit duplicate at that point.
var game_state_snapshot: Dictionary:
	get:
		return GameState.state
	set(_value):
		pass
var phase_type: GameStateData.Phase

# Abstract methods that must be implemented by concrete phases
func enter_phase(state_snapshot: Dictionary) -> void:
	game_state_snapshot = state_snapshot
	_ev_baseline = _ev_snapshot()
	# Codex: Adeptus Custodes (11e) "At the start of any phase" abilities
	# (Moment Shackle, Neutronium Cascade Mine, Sword of the Throne —
	# CustodesAbilities.gd, WP-C7): queued as event windows BEFORE the phase's
	# own start rules, so the first window the phase opens resolves them first.
	_ev_deferred.append_array(_cus11e_abilities().phase_start_entries(int(phase_type)))
	# WP-S4: Space Wolves start-of-phase ability cards (Slayer's Oath, Headhunters,
	# Healing Balms, High King of Fenris, Njal's psychic powers, Haywire Mine).
	_ev_deferred.append_array(_sw11e_abilities().phase_start_entries(int(phase_type), _ev_deferred))
	# WP-M2a: Codex: Space Marines (11e) start-of-phase enhancement cards (Auspex Triangulation Shrines, Damocles-class Uplink).
	_ev_deferred.append_array(load("res://scripts/codex/space_marines/SMDetachmentsA.gd").phase_start_entries(int(phase_type), _ev_deferred))
	# WP-M2b: Codex: Space Marines (11e) Tactical Insight (doctrine sync) + Narthecis Gauntlet Command-phase card.
	load("res://scripts/codex/space_marines/SMDetachmentsB.gd").on_phase_enter(int(phase_type))
	_ev_deferred.append_array(load("res://scripts/codex/space_marines/SMDetachmentsB.gd").phase_start_entries(int(phase_type), _ev_deferred))
	# WP-M4b: Codex: Space Marines M4b start-of-phase ability cards (Strategic Acumen,
	# Spiritual Leader, Rampart, Teleport Homer, Tigurius' / the Librarian's psychic
	# powers, Haywire Mine, Signum Array) — SMAbilitiesB.gd.
	_ev_deferred.append_array(load("res://scripts/codex/space_marines/SMAbilitiesB.gd").phase_start_entries(int(phase_type), _ev_deferred))
	# WP-M4c: Space Marines (M4c datasheets) start-of-phase cards (Strategic Acumen, Narthecium,
	# Master of Shadows, Seeker of the Unfound, Forgefather, Overlapping Destruction, Master Tactician).
	_ev_deferred.append_array(load("res://scripts/codex/space_marines/SMAbilitiesC.gd").phase_start_entries(int(phase_type), _ev_deferred))
	# WP-M4a: Space Marines start-of-phase cards (Teleport Homer, Forward Assault Warsuit, Author of the Codex, Thunderous Force, Soul Sight, Omni-scramblers, Might of Heroes).
	_ev_deferred.append_array(_sm11e_abilities_a().phase_start_entries(int(phase_type), _ev_deferred))
	_on_phase_enter()
	# (A phase that ended inside its own entry does not carry them over.)
	var pm_now = get_node_or_null("/root/PhaseManager")
	if pm_now != null and pm_now.current_phase_instance != null and pm_now.current_phase_instance != self:
		_ev_deferred = _ev_deferred.filter(func(e): return str(e.get("window_id", "")) != "phase_start")
	# Units destroyed / battle-shocked by phase-start rules (e.g. Big Gob).
	_window_events_flush({})
	# Codex: Adeptus Custodes (11e) "at the start of any phase" enhancements —
	# Pareldor's Caducatrix, Inspirational Exemplar, Sally Forth (Charge phase):
	# a rule-only window, opened only when someone has an offer (CustodesEnhancements.gd, WP-C46).
	_cus11e_open_phase_start_window()

func exit_phase() -> void:
	_on_phase_exit()
	# Codex: Adeptus Custodes — the ka'tah effects that lasted for this phase
	# expire (CustodesKatah.gd; Conservai lasts until the end of the turn).
	_cus11e_katah().on_phase_exit(int(phase_type))
	# Codex: Adeptus Custodes (11e) detachment / enhancement phase-scoped choices expire (WP-C46).
	_cus11e_det().on_phase_end(int(phase_type))

	# Clear debug visualizations on any phase exit
	_clear_debug_visualizations()

# Helper method to clear debug visualizations safely
func _clear_debug_visualizations() -> void:
	# Try to get the main scene root
	var main_loop = Engine.get_main_loop()
	if not main_loop or not main_loop is SceneTree:
		return

	var root = main_loop.current_scene
	if not root:
		return

	# Navigate to the LoSDebugVisual node
	var board_root = root.get_node_or_null("BoardRoot")
	if not board_root:
		return

	var los_debug = board_root.get_node_or_null("LoSDebugVisual")
	if los_debug and is_instance_valid(los_debug) and los_debug.has_method("clear_all_debug_visuals"):
		los_debug.clear_all_debug_visuals()

func _on_phase_enter() -> void:
	# Override in concrete phases for phase-specific setup
	pass

func _on_phase_exit() -> void:
	# Override in concrete phases for phase-specific cleanup
	pass

# Validate if an action is legal in this phase
func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	# Debug mode bypasses normal validation
	if action_type == "DEBUG_MOVE":
		# Only allow if debug mode is active
		if DebugManager and DebugManager.is_debug_active():
			return {"valid": true}
		else:
			return {"valid": false, "reason": "Debug mode not active", "errors": ["Debug mode must be active to use DEBUG_MOVE"]}

	# Override in concrete phases for phase-specific validation
	return {"valid": true, "errors": []}

# Get list of available actions for current game state
func get_available_actions() -> Array:
	# Override in concrete phases to return available actions
	return []

# Process a validated action and return state changes
func process_action(action: Dictionary) -> Dictionary:
	# Override in concrete phases for action processing
	return {"success": false, "error": "Not implemented"}

# Execute an action (validate + process + apply)
func execute_action(action: Dictionary) -> Dictionary:
	DebugLogger.info(str("[BasePhase] Executing action: ", action.get("type", "UNKNOWN")))
	DebugLogger.info(str("[BasePhase] For unit: ", action.get("unit_id", "N/A")))

	var _action_type := str(action.get("type", ""))
	var _perf_t0 := Time.get_ticks_usec()
	var result: Dictionary
	if _action_type in WINDOW_ACTION_TYPES:
		# Stratagem-window answers are handled generically here, before any
		# subclass validation (design §3.1) — every phase gets them for free.
		var window_validation = _validate_window_action(action)
		if not window_validation.valid:
			var w_errors = window_validation.get("errors", [])
			DebugLogger.info(str("[BasePhase] Window action validation failed: ", w_errors))
			return {"success": false, "error": ", ".join(w_errors) if not w_errors.is_empty() else "Action not allowed", "errors": w_errors}
		if not action.has("player"):
			action["player"] = int(_window_pending.get("player", get_current_player()))
		_window_events_begin(action)
		result = _process_window_action(action)
	else:
		# While a stratagem window waits for a human, nothing else may happen in
		# the phase — the decider's answer resumes the interrupted flow.
		if has_pending_stratagem_window() and not _window_exempt_action(_action_type):
			var wait_msg := "Waiting for Player %d to decide on a stratagem" % int(_window_pending.get("player", 0))
			DebugLogger.info("[BasePhase] %s — rejected %s" % [wait_msg, _action_type])
			return {"success": false, "error": wait_msg, "errors": [wait_msg], "stratagem_window_pending": true}

		# Tutorial allow-list gate (PRPs/tutorial_system.md §5.2): while a lesson is
		# active only the step's taught actions (plus AI/P2 and DECLINE_* safety
		# actions) pass. Every input path funnels through here — mouse, keyboard,
		# pad, dialogs, scenario dispatch — so no per-controller surgery is needed.
		var _tutorial = get_node_or_null("/root/TutorialManager")
		if _tutorial != null and _tutorial.active and not _tutorial.is_action_allowed(action):
			_tutorial.on_action_blocked(action)
			return {"success": false, "error": "Tutorial: follow da current step",
				"errors": ["tutorial_locked"], "tutorial_blocked": true}

		var validation = validate_action(action)
		if not validation.valid:
			DebugLogger.info(str("[BasePhase] Action validation failed: ", validation.errors))
			# Populate BOTH `errors` (the array, for callers that read the list) and a joined
			# `error` string. The UI handlers in Main.gd read result.error and otherwise fall
			# back to a generic "Unknown error", silently dropping the real rejection reason
			# (e.g. "Cannot select fighter — the Pile In step must finish first").
			var raw_errors = validation.get("errors", [])
			var error_text: String = ", ".join(raw_errors) if (raw_errors is Array and not raw_errors.is_empty()) else "Action not allowed"
			return {"success": false, "error": error_text, "errors": raw_errors}

		_window_events_begin(action)
		result = process_action(action)
	_ev_depth -= 1
	var _ev_outer := _ev_depth == 0
	var _perf_ms := (Time.get_ticks_usec() - _perf_t0) / 1000.0
	if _perf_ms >= 16.0:
		DebugLogger.info("[PERF] BasePhase.process_action(%s) took %.1fms" % [str(action.get("type", "UNKNOWN")), _perf_ms])
	if result.success:
		DebugLogger.info("[BasePhase] Action processed successfully")
		# Apply the state changes if they exist
		if result.has("changes") and result.changes is Array:
			PhaseManager.apply_state_changes(result.changes)

			# ISS-024: no refresh needed — the snapshot property reads
			# live state.

		# Codex: Space Marines (11e) MORTIS SNARES (SMCodex11e.gd): an enemy unit that ended a
		# move within range of a snared objective (diffs already applied; recorded with the action).
		if _ev_outer:
			var sm11e_snare: Array = _sm11e_codex().on_action_applied(str(GameStateData.Phase.find_key(phase_type)).capitalize())
			if not sm11e_snare.is_empty():
				if result.get("changes", null) is Array:
					result.changes.append_array(sm11e_snare)
				else:
					result["changes"] = sm11e_snare

		# Units this action destroyed / battle-shocked open their event
		# windows now (design §3: unit_destroyed, unit_battle_shocked,
		# enemy_unit_has_attacked) — before the action is recorded.
		if _ev_outer:
			_window_events_flush(result)

		# Attach human-readable log_text from result to the action dict
		if result.has("log_text") and result.log_text != "":
			action["_log_text"] = result.log_text

		# Attach diffs/changes to the action for replay recording
		# (In single-player, actions bypass GameManager so result_applied never fires.
		# The replay system reads these diffs from the phase_action_taken signal instead.)
		if result.has("changes") and result.changes is Array:
			action["_replay_diffs"] = result.changes

		# A stratagem window is now waiting for a human: stamp it on the result
		# so NetworkManager can mirror it on the client (re-emit
		# stratagem_window_opened there, like reactive_stratagem_opportunity).
		if has_pending_stratagem_window():
			result["stratagem_window_opened"] = _window_pending.duplicate(true)

		if not action.has("player"):
			action["player"] = get_current_player()

		# T09: every unit this action left "acted this phase" is announced
		# (unit_acted_in_phase) before action_taken, with the state applied.
		_t09_emit_newly_acted()

		# Record the action
		DebugLogger.info("[BasePhase] Emitting action_taken signal")
		emit_signal("action_taken", action)

		# Check if this action completes the phase.
		# Guard: if process_action already emitted phase_completed (causing PhaseManager
		# to transition out), don't re-emit — that would cascade as a phantom completion
		# signal on the next phase. See issue #331.
		var pm = get_node_or_null("/root/PhaseManager")
		var still_current: bool = pm == null or pm.current_phase_instance == self
		if still_current and _should_complete_phase():
			if _window_blocks_phase_completion():
				# F1: a stratagem window / follow-up opened by this very action
				# (e.g. the last shooter's unit_has_shot / unit_destroyed window)
				# still waits for a decision. The action that answers it runs
				# this check again, so the phase completes then — never with
				# the window left on a dead phase instance.
				DebugLogger.info("[StratagemWindow] phase would complete, but a stratagem window / follow-up is pending (P%d) — completion deferred until it is answered" % get_pending_stratagem_window_decider())
			else:
				emit_signal("phase_completed")
	else:
		DebugLogger.info("[BasePhase] Action processing failed")

	return result

# Check if the phase should be completed
func _should_complete_phase() -> bool:
	# Override in concrete phases for phase-specific completion logic
	return false

# ============================================================================
# T09 — "has acted this phase" (design doc §8, exhaustion shading)
# ============================================================================
# A unit has acted once its own step in the phase is over: Movement — its move
# ended (or it remained stationary / arrived from reserves); Shooting — it has
# shot; Charge — its charge was resolved or skipped; Fight — it has fought.
# Phases with such a per-unit step override has_unit_acted_this_phase() and
# answer from the synced unit flags, so the answer also holds on a network
# client (whose phase never runs execute_action) and after a mid-phase load.
# Every other phase keeps the default: no unit has acted.
# execute_action() emits unit_acted_in_phase(unit_id) once per flip to true.

var _t09_acted_units: Dictionary = {}  # unit_id -> true at the last check

func has_unit_acted_this_phase(_unit_id: String) -> bool:
	return false

## T09 helper: whether unit_id's flags[flag] is set (false for a missing unit
## or flags that are not a dictionary).
func _t09_unit_flag(unit_id: String, flag: String) -> bool:
	var flags = get_unit(unit_id).get("flags", {})
	if typeof(flags) != TYPE_DICTIONARY:
		return false
	return true if flags.get(flag, false) else false

## T09 helper: whether unit_id belongs to the player whose turn it is.
func _t09_is_active_players(unit_id: String) -> bool:
	var unit := get_unit(unit_id)
	return not unit.is_empty() and int(unit.get("owner", 0)) == get_current_player()

## The ids of every unit that has acted this phase, sorted.
func get_units_acted_this_phase() -> Array:
	var out: Array = []
	for unit_id in game_state_snapshot.get("units", {}):
		if has_unit_acted_this_phase(str(unit_id)):
			out.append(str(unit_id))
	out.sort()
	return out

func _t09_emit_newly_acted() -> void:
	# An action that ended the phase from inside process_action has already
	# swapped this instance out (PhaseManager queue_frees it): the new phase
	# owns the units, so nothing is announced from here.
	if is_queued_for_deletion():
		return
	var now := {}
	for unit_id in get_units_acted_this_phase():
		now[unit_id] = true
		if not _t09_acted_units.has(unit_id):
			DebugLogger.info("[BasePhase] T09: %s has acted this phase (%s) — unit_acted_in_phase" % [unit_id, str(GameStateData.Phase.find_key(phase_type))])
			emit_signal("unit_acted_in_phase", unit_id)
	_t09_acted_units = now

# Utility methods for interacting with game state
func get_current_player() -> int:
	# Always get the current active player from live GameState, not the snapshot
	# This ensures we see updates made by TurnManager
	return GameState.get_active_player()

func get_turn_number() -> int:
	return game_state_snapshot.get("meta", {}).get("turn_number", 1)

func get_units_for_player(player: int, include_destroyed: bool = false) -> Dictionary:
	var player_units = {}
	var units = game_state_snapshot.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("owner", 0) == player:
			if not include_destroyed and _is_unit_destroyed_check(unit):
				continue
			player_units[unit_id] = unit

	return player_units

static func _is_unit_destroyed_check(unit: Dictionary) -> bool:
	"""Check if a unit dictionary represents a fully destroyed unit (all models dead)."""
	var models = unit.get("models", [])
	if models.is_empty():
		return true
	for model in models:
		if model.get("alive", true):
			return false
	return true

func get_unit(unit_id: String) -> Dictionary:
	var units = game_state_snapshot.get("units", {})
	return units.get(unit_id, {})

func get_deployment_zone_for_player(player: int) -> Dictionary:
	var zones = game_state_snapshot.get("board", {}).get("deployment_zones", [])
	for zone in zones:
		if zone.get("player", 0) == player:
			return zone
	return {}

# Create a standardized action dictionary
func create_action(action_type: String, parameters: Dictionary = {}) -> Dictionary:
	var action = {
		"type": action_type,
		"phase": phase_type,
		"player": get_current_player(),
		"turn": get_turn_number(),
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Add parameters
	for key in parameters:
		action[key] = parameters[key]
	
	return action

# Create a standardized result dictionary
func create_result(success: bool, changes: Array = [], error: String = "") -> Dictionary:
	var result = {
		"success": success,
		"phase": phase_type,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	if success:
		result["changes"] = changes
	else:
		result["error"] = error
	
	return result

# Update local game state snapshot (call this after applying changes)
func update_local_state(new_snapshot: Dictionary) -> void:
	game_state_snapshot = new_snapshot

# Log a message for this phase
func log_phase_message(message: String, level: String = "INFO") -> void:
	DebugLogger.info(str("[%s][%s] %s" % [str(phase_type), level, message]))


# ============================================================================
# STRATAGEM WINDOW FRAMEWORK (design §3.1 / §3.2 / §6)
# ============================================================================

func has_pending_stratagem_window() -> bool:
	return not _window_pending.is_empty()

func get_pending_stratagem_window() -> Dictionary:
	return _window_pending

## Owner of the pending window (0 when none) — AIPlayer idles on a human's.
func get_pending_stratagem_window_decider() -> int:
	return int(_window_pending.get("player", 0))

## True while a stratagem window or a used stratagem's follow-up still waits
## for a decision (the phase-specific follow-ups report their owner through
## get_pending_stratagem_window_decider) — the phase must not complete then.
func _window_blocks_phase_completion() -> bool:
	return has_pending_stratagem_window() or _window_followup_pending or get_pending_stratagem_window_decider() > 0

## Network turn layer (NetworkManager.validate_action): an action by the
## NON-active player that belongs to the follow-up they own (e.g. the SCARPER!
## reactive normal move, made with the ordinary movement actions during the
## opponent's turn) is not refused with "Not your turn". Authority (claimed
## player == sending peer) is still checked there, and the phase's own
## follow-up gate still decides which actions / units are legal.
func allows_cross_turn_action(action: Dictionary) -> bool:
	var claimed := int(action.get("player", -1))
	return claimed > 0 and get_pending_stratagem_window_decider() == claimed

## F4: on a networked CLIENT no window is ever opened locally — the HOST opens
## it, stamps stratagem_window_opened on its result and NetworkManager mirrors
## it here (mirror_stratagem_window). Opening one locally as well (from an
## optimistically executed action or the client's own phase entry) built a
## second, stale queue / resume state beside the mirror.
func _is_network_client() -> bool:
	var nm = get_node_or_null("/root/NetworkManager")
	return nm != null and nm.has_method("is_networked") and nm.is_networked() \
		and nm.has_method("is_host") and not nm.is_host()

## Actions that stay legal while a window is pending (debug / UI-only).
func _window_exempt_action(action_type: String) -> bool:
	return action_type.begins_with("DEBUG_")

## Open one stratagem window for `player`. Returns true when the phase is now
## PAUSED for a human decision (resume_method(ctx, window_result) is called
## once the decider answers and the queue drains); false when there was
## nothing to wait for (no offers, suppressed, or an AI decided synchronously)
## — the caller continues its flow itself and must merge
## consume_window_diffs() into its own result.
func open_stratagem_window(player: int, window_id: String, ctx: Dictionary, resume_method: String) -> bool:
	return open_stratagem_windows([{"player": player, "window_id": window_id, "ctx": ctx}], resume_method, ctx)

## Active player's window first, then the non-active player's (design §3.1:
## movement_phase_start/end, fight_phase_end).
func open_stratagem_window_both_players(window_id: String, ctx: Dictionary, resume_method: String) -> bool:
	var active := get_current_player()
	var other := 2 if active == 1 else 1
	return open_stratagem_windows([
		{"player": active, "window_id": window_id, "ctx": ctx},
		{"player": other, "window_id": window_id, "ctx": ctx}], resume_method, ctx)

## Queue several windows at one hook; they open in order and the phase
## resumes (resume_method) when the queue is empty.
func open_stratagem_windows(entries: Array, resume_method: String, resume_ctx: Dictionary = {}) -> bool:
	if _is_network_client():
		DebugLogger.info("[StratagemWindow] network client — %s not opened locally (the host opens it; its result is mirrored)" % str(entries.map(func(e): return e.get("window_id", "?"))))
		return false
	if has_pending_stratagem_window() or _window_followup_pending:
		if resume_method == "":
			# A resume-less (event) window nests: queue it and open it as soon
			# as the current window / follow-up closes — never lost, never
			# clobbering the pending one.
			_ev_deferred.append_array(entries)
			DebugLogger.info("[StratagemWindow] %s queued behind pending window %s" % [
				str(entries.map(func(e): return e.get("window_id", "?"))), str(_window_pending.get("window_id", "followup"))])
			return false
		# Nested hook windows (with a resume method) are not supported — say
		# so loudly instead of silently clobbering the pending one.
		_window_error("open_stratagem_windows(%s) while window %s is still pending — not opened" % [
			str(entries.map(func(e): return e.get("window_id", "?"))), str(_window_pending.get("window_id", "followup"))])
		return false
	var tutorial = get_node_or_null("/root/TutorialManager")
	# meta.tutorial is set while a lesson BOOTS into its phase, before
	# TutorialManager.active: the shooting panel's real phase-entry
	# auto-selection (r5:F3) must not open a window there either.
	if tutorial != null and (tutorial.active or bool(GameState.state.get("meta", {}).get("tutorial", false))):
		# Scripted lessons drive one taught action at a time; an unrequested
		# stratagem prompt would derail the step. Windows stay closed.
		DebugLogger.info("[StratagemWindow] tutorial active — windows %s not opened" % str(entries.map(func(e): return e.get("window_id", "?"))))
		return false
	if resume_method != "" and _ev_depth > 0:
		# F10: a hook opened mid-action (e.g. the post-shot unit_has_shot /
		# enemy_has_shot windows, after the shot's damage is applied) comes
		# AFTER the events that action already caused: units destroyed by the
		# shot raise unit_destroyed (before Deadly Demise) / enemy_unit_has_attacked
		# now, and _process_window_queue puts them at the front of the queue.
		_window_events_detect()
	_window_queue.append_array(entries)
	_window_resume_method = resume_method
	_window_resume_ctx = resume_ctx.duplicate(true)
	return _process_window_queue()

## Codex: Adeptus Custodes ka'tah abilities (CustodesKatah.gd) are offered in
## the stratagem windows of their WHEN. Loaded lazily (no preload chain into
## every phase script).
static func _cus11e_katah():
	return load("res://scripts/codex/custodes/CustodesKatah.gd")

## Codex: Adeptus Custodes (11e) detachment rules + enhancements (WP-C46).
static func _cus11e_det():
	return load("res://scripts/codex/custodes/CustodesDetachments.gd")

## The start-of-phase rule window (CustodesEnhancements.WINDOW_PHASE_START):
## resume-less, so the phase's own entry flow is untouched — a pending window
## (e.g. the Fight phase's start window) queues it behind; while it waits for
## a human, the phase's actions wait too.
func _cus11e_open_phase_start_window() -> void:
	var e = _cus11e_det().enh()
	if e == null or PhaseManager.get_current_phase_instance() != self:
		return
	var entries: Array = e.phase_start_window_entries()
	if entries.is_empty():
		return
	DebugLogger.info("[StratagemWindow] start of phase %d — Codex: Adeptus Custodes enhancement window(s) for %s" % [int(phase_type), str(entries.map(func(x): return x.player))])
	open_stratagem_windows(entries, "", {})

## Codex: Adeptus Custodes stratagems (WP-C5, CustodesCodex11e.gd): the new
## windows' hooks and the effect consumers the phases call. Loaded lazily.
static func _cus11e_codex():
	return load("res://scripts/codex/custodes/CustodesCodex11e.gd")

## Codex: Adeptus Custodes datasheet abilities (WP-C7, CustodesAbilities.gd):
## the phase_start window and the phases' passive hooks. Loaded lazily.
static func _cus11e_abilities():
	return load("res://scripts/codex/custodes/CustodesAbilities.gd")

## Codex: Space Marines (11e) Space Wolves datasheet abilities (WP-S4,
## SWAbilities11e.gd): the phase_start cards and the phases' passive hooks.
static func _sw11e_abilities():
	return load("res://scripts/codex/space_wolves/SWAbilities11e.gd")

## Codex: Space Marines (11e) generic detachment stratagems (WP-M3a) — loaded lazily.
static func _sm11e_codex():
	return load("res://scripts/codex/space_marines/SMCodex11e.gd")
## WP-M4a: Codex: Space Marines (11e) generic datasheet abilities, M4a list
## (SMAbilitiesA.gd): the phase_start cards and the phases' passive hooks.
static func _sm11e_abilities_a():
	return load("res://scripts/codex/space_marines/SMAbilitiesA.gd")

## Codex: Adeptus Custodes SUPERHUMAN FOCUS (WP-C5, CustodesCodex11e.gd): the
## phase_end window ("End of any phase", both players, active first). Called by
## PhaseManager._on_phase_completed before it advances: true = the window now
## waits for a human and the phase completes from its resume; false = advance
## now (no Custodes phase_end stratagem, or an AI decided synchronously — its
## diffs are already applied by StratagemManager.use_stratagem). Once per phase
## instance, so the resume's own phase_completed advances.
var _cus11e_phase_end_done: bool = false

func cus11e_open_phase_end_window() -> bool:
	if _cus11e_phase_end_done or GameConstants.edition < 11:
		return false
	_cus11e_phase_end_done = true
	var codex = _cus11e_codex()
	if not (codex.player_has_window_stratagem(1, "phase_end") or codex.player_has_window_stratagem(2, "phase_end")):
		return false
	if has_pending_stratagem_window() or _window_followup_pending:
		_window_error("phase_end window not opened: window %s / a follow-up is still pending at the end of the phase" % str(_window_pending.get("window_id", "followup")))
		return false
	var ctx := {"phase": StratagemManager._phase_to_string(GameState.get_current_phase())}
	if open_stratagem_window_both_players("phase_end", ctx, "_cus11e_resume_after_phase_end"):
		log_phase_message("End of the %s phase waits for Player %d's phase_end stratagem decision" % [ctx.phase, get_pending_stratagem_window_decider()])
		return true
	var sync := consume_window_diffs()
	if not sync.is_empty():
		log_phase_message("phase_end: %d stratagem diff(s) applied by an AI decision at the end of the %s phase" % [sync.size(), ctx.phase])
	return false

func _cus11e_resume_after_phase_end(_ctx: Dictionary, _window_result: Dictionary) -> Dictionary:
	log_phase_message("phase_end windows answered — ending the phase")
	emit_signal("phase_completed")
	return create_result(true, [])

## Everything `player` may use in this window: the stratagems
## (StratagemManager.get_window_offers) followed by the ka'tah cards.
## katah_only: the ka'tah cards alone (a window re-opened after a stratagem).
func _window_offers_for(player: int, window_id: String, ctx: Dictionary, katah_only: bool = false) -> Array:
	# WP-O6: get_all_window_offers = window stratagems + Codex: Orks (11e) datasheet abilities.
	var offers: Array = [] if katah_only else StratagemManager.get_all_window_offers(player, window_id, ctx)
	offers.append_array(_cus11e_katah().window_offers(player, window_id, ctx))
	return offers

## Re-open `window_id` for `player` next (front of the queue): after a ka'tah
## use with everything still offered; after a stratagem use (katah_only) only
## when a ka'tah card is still usable there. The queue opens it as usual —
## nothing left to offer simply resumes the phase.
func _queue_katah_reopen(player: int, window_id: String, ctx: Dictionary, katah_only: bool) -> void:
	var rctx: Dictionary = ctx.duplicate(true)
	if katah_only and _cus11e_katah().window_offers(player, window_id, rctx).is_empty():
		return
	_window_queue.push_front({"player": player, "window_id": window_id, "ctx": rctx, "katah_only": katah_only})
	DebugLogger.info("[StratagemWindow] %s for P%d re-queued (%s)" % [window_id, player, "ka'tah cards only" if katah_only else "after a ka'tah use"])

## Extra result keys produced by window follow-ups since the last call
## (never "success" / "changes" — callers merge without overwriting).
func consume_window_result_extra() -> Dictionary:
	var e := _window_result_extra
	_window_result_extra = {}
	return e

## Diffs applied by windows that resolved synchronously (AI decider) since the
## last call. The phase merges them into the result of the action that opened
## the window so replay / network clients see the CP + effect changes.
func consume_window_diffs() -> Array:
	var d = _window_sync_diffs
	_window_sync_diffs = []
	return d

func _is_ai_window_decider(player: int) -> bool:
	var ai = get_node_or_null("/root/AIPlayer")
	return ai != null and ai.has_method("is_ai_player") and ai.is_ai_player(player)

func _process_window_queue() -> bool:
	_window_events_pull_deferred()
	while not _window_queue.is_empty():
		var entry: Dictionary = _window_queue.pop_front()
		var player := int(entry.get("player", 0))
		var window_id := str(entry.get("window_id", ""))
		var ctx: Dictionary = entry.get("ctx", {}).duplicate(true)
		ctx["window_id"] = window_id
		if not ctx.has("phase"):
			ctx["phase"] = StratagemManager._phase_to_string(GameState.get_current_phase())
		if _window_suppressed.has("%d:%s" % [player, window_id]):
			DebugLogger.info("[StratagemWindow] %s for P%d suppressed (\"don't offer again this phase\")" % [window_id, player])
			_window_event_closed(window_id, ctx, false)
			continue
		var katah_only := bool(entry.get("katah_only", false))
		var offers: Array = _window_offers_for(player, window_id, ctx, katah_only)
		if offers.is_empty():
			DebugLogger.info("[StratagemWindow] %s for P%d — no offers" % [window_id, player])
			_window_event_closed(window_id, ctx, false)
			continue
		if _is_ai_window_decider(player):
			var decision: Dictionary = AIDecisionMaker.decide_window_stratagem(player, window_id, offers, ctx)
			# Codex: Adeptus Custodes ka'tah abilities (CustodesKatah.gd) leave the
			# window open: apply each one the AI picks, then let it decide again
			# on what is still offered (another readied unit, the stratagems).
			var katah_guard := 0
			while decision.get("use", false) and _cus11e_katah().is_katah_offer_id(str(decision.get("stratagem_id", ""))) and katah_guard < 24:
				katah_guard += 1
				var k_res = _apply_window_use(player, window_id, str(decision.get("stratagem_id", "")),
					str(decision.get("target_unit_id", "")), decision.get("context", {}), ctx, offers)
				if not k_res.get("success", false):
					_window_error("AI P%d ka'tah decision for %s failed: %s — treated as decline" % [player, window_id, k_res.get("error", "?")])
					decision = {"use": false}
					break
				_window_sync_diffs.append_array(k_res.get("diffs", []))
				DebugLogger.info("[StratagemWindow] AI P%d used ka'tah %s on %s in %s" % [player, decision.get("stratagem_id", ""), decision.get("target_unit_id", ""), window_id])
				offers = _window_offers_for(player, window_id, ctx, katah_only)
				decision = {"use": false} if offers.is_empty() else AIDecisionMaker.decide_window_stratagem(player, window_id, offers, ctx)
			if offers.is_empty():
				emit_signal("stratagem_window_closed", player, window_id, true)
				_window_event_closed(window_id, ctx, true)
				continue
			if decision.get("use", false):
				var sync_mark := _window_sync_diffs.size()
				var use_res = _apply_window_use(player, window_id, str(decision.get("stratagem_id", "")),
					str(decision.get("target_unit_id", "")), decision.get("context", {}), ctx, offers)
				if use_res.get("success", false):
					# Replay order: the use's own diffs (CP, effect flags) come before
					# whatever its follow-up already appended synchronously (e.g. a
					# follow-up that clears the flag the use set).
					var followup_diffs: Array = _window_sync_diffs.slice(sync_mark)
					_window_sync_diffs = _window_sync_diffs.slice(0, sync_mark)
					_window_sync_diffs.append_array(use_res.get("diffs", []))
					_window_sync_diffs.append_array(followup_diffs)
					DebugLogger.info("[StratagemWindow] AI P%d used %s on %s in %s" % [player, decision.get("stratagem_id", ""), decision.get("target_unit_id", ""), window_id])
					# The AI decided inside the phase (no AI-submitted action), so
					# tell AIPlayer — its turn summary counts USE_WINDOW_STRATAGEM.
					var ai_node = get_node_or_null("/root/AIPlayer")
					if ai_node and ai_node.has_method("record_window_stratagem_use"):
						ai_node.record_window_stratagem_use(player, window_id, str(decision.get("stratagem_id", "")),
							str(use_res.get("stratagem_name", decision.get("stratagem_id", ""))), str(decision.get("target_unit_id", "")),
							str(decision.get("context", {}).get("secondary_id", "")) if typeof(decision.get("context", {})) == TYPE_DICTIONARY else "",
							int(use_res.get("cp_cost", 0)))
					emit_signal("stratagem_window_closed", player, window_id, true)
					_window_event_closed(window_id, ctx, true)
					# A ka'tah still usable in this window is offered next (CustodesKatah.gd).
					_queue_katah_reopen(player, window_id, ctx, true)
					if use_res.get("paused", false):
						return true
					# Codex: Orks (11e) free rule choice (WP-O34): re-offer the window for its stratagems.
					if use_res.get("reopen_window", false):
						_window_queue.push_front(entry)
					# Events the stratagem caused (units it destroyed / battle-shocked)
					# open their windows next, before the rest of the queue.
					_window_events_detect()
					_window_events_pull_deferred()
					continue
				_window_error("AI P%d decision for %s failed: %s — treated as decline" % [player, window_id, use_res.get("error", "?")])
			DebugLogger.info("[StratagemWindow] AI P%d declined %s (%d offer(s))" % [player, window_id, offers.size()])
			emit_signal("stratagem_window_closed", player, window_id, false)
			_window_event_closed(window_id, ctx, false)
			_window_events_detect()
			_window_events_pull_deferred()
			continue
		_window_pending = {"player": player, "window_id": window_id, "offers": offers, "ctx": ctx}
		DebugLogger.info("[StratagemWindow] OPEN %s for P%d — %d offer(s): %s" % [
			window_id, player, offers.size(), str(offers.map(func(o): return o.get("name", "?")))])
		emit_signal("stratagem_window_opened", player, window_id, offers, ctx)
		return true
	return false

func _apply_window_use(player: int, window_id: String, stratagem_id: String, target_unit_id: String, action_ctx, window_ctx: Dictionary, offers: Array = []) -> Dictionary:
	var use_ctx: Dictionary = window_ctx.duplicate(true)
	if typeof(action_ctx) == TYPE_DICTIONARY:
		use_ctx.merge(action_ctx, true)
	use_ctx["window_id"] = window_id
	# LIVE-10: name the chosen option (HULKING BRUTES' upgrade, VINDICTIVE
	# ARTILLERISTS' profile) in the player-visible "Used ..." log line.
	var variant_label := _window_variant_label(offers, stratagem_id, target_unit_id, str(use_ctx.get("variant_id", "")))
	if variant_label != "":
		use_ctx["variant_label"] = variant_label
	# Codex: Adeptus Custodes ka'tah ability (CustodesKatah.gd) — no CP, no
	# stratagem bookkeeping; the module validates, applies and logs it.
	if _cus11e_katah().is_katah_offer_id(stratagem_id):
		var k_res: Dictionary = _cus11e_katah().use_katah(player, stratagem_id, target_unit_id, use_ctx)
		if not k_res.get("success", false):
			return {"success": false, "error": str(k_res.get("error", "ka'tah use failed"))}
		var k_name := str(k_res.get("stratagem_name", stratagem_id))
		_window_last_result = {"used": true, "player": player, "window_id": window_id, "katah": true,
			"stratagem_id": stratagem_id, "target_unit_id": target_unit_id,
			"stratagem_name": k_name, "diffs": k_res.get("diffs", [])}
		return {"success": true, "diffs": k_res.get("diffs", []), "paused": false, "followup": {}, "stratagem_name": k_name}
	var res: Dictionary = StratagemManager.use_stratagem(player, stratagem_id, target_unit_id, use_ctx)
	if not res.get("success", false):
		return {"success": false, "error": str(res.get("error", "stratagem use failed"))}
	_window_last_result = {"used": true, "player": player, "window_id": window_id,
		"stratagem_id": stratagem_id, "target_unit_id": target_unit_id,
		"stratagem_name": str(res.get("stratagem_name", stratagem_id)), "diffs": res.get("diffs", [])}
	var paused := false
	var followup: Dictionary = res.get("followup", {})
	var use_diffs: Array = res.get("diffs", [])
	if not followup.is_empty():
		DebugLogger.info("[StratagemWindow] %s returned follow-up %s — handing to %s" % [stratagem_id, str(followup.get("type", "?")), get_script().resource_path.get_file()])
		# Follow-ups that need no phase interaction run here in every phase
		# (new_reserve_unit — INFESTED WAR ZONE); the rest go to the phase.
		var generic: Dictionary = _execute_generic_window_followup(player, window_id, followup, use_ctx)
		if generic.get("handled", false):
			use_diffs = use_diffs.duplicate()
			use_diffs.append_array(generic.get("diffs", []))
			_window_last_result["diffs"] = use_diffs
		else:
			paused = _execute_window_followup(player, window_id, followup, use_ctx)
			_window_followup_pending = paused
	return {"success": true, "diffs": use_diffs, "paused": paused, "followup": followup,
		"stratagem_name": str(res.get("stratagem_name", stratagem_id)), "cp_cost": int(res.get("cp_cost", 0)),
		# Codex: Orks (11e) rule choice (WP-O34): the window is offered again afterwards.
		"reopen_window": bool(res.get("reopen_window", false))}

func _validate_window_action(action: Dictionary) -> Dictionary:
	if not has_pending_stratagem_window():
		return {"valid": false, "errors": ["No stratagem window is waiting for a decision"]}
	var decider := int(_window_pending.get("player", 0))
	if action.has("player") and int(action.get("player", 0)) != decider:
		return {"valid": false, "errors": ["Player %d decides this stratagem window, not Player %d" % [decider, int(action.get("player", 0))]]}
	var window_id := str(action.get("window_id", _window_pending.get("window_id", "")))
	if window_id != str(_window_pending.get("window_id", "")):
		return {"valid": false, "errors": ["Window %s is not open (pending: %s)" % [window_id, _window_pending.get("window_id", "")]]}
	if str(action.get("type", "")) == "DECLINE_WINDOW_STRATAGEM":
		return {"valid": true, "errors": []}
	var sid := str(action.get("stratagem_id", ""))
	var tid := str(action.get("target_unit_id", ""))
	var actx = action.get("context", {})
	var variant := str(actx.get("variant_id", "")) if typeof(actx) == TYPE_DICTIONARY else ""
	for offer in _window_pending.get("offers", []):
		if str(offer.get("stratagem_id", "")) != sid:
			continue
		for t in offer.get("targets", []):
			if str(t.get("unit_id", "")) != tid:
				continue
			if variant != "":
				var variant_ok := false
				for v in t.get("variants", []):
					if str(v.get("id", "")) == variant:
						variant_ok = true
				if not variant_ok:
					return {"valid": false, "errors": ["Variant %s is not offered for %s" % [variant, sid]]}
			elif bool(t.get("require_variant", false)) and not t.get("variants", []).is_empty():
				return {"valid": false, "errors": ["%s needs one of its options to be chosen" % offer.get("name", sid)]}
			if t.has("secondary") and typeof(actx) == TYPE_DICTIONARY and str(actx.get("secondary_id", "")) == "":
				return {"valid": false, "errors": ["%s needs a %s choice" % [offer.get("name", sid), t.secondary.get("kind", "secondary")]]}
			# The secondary choice must be one of the OFFERED options — an
			# action from a network client (or a stale dialog) naming any other
			# unit / objective is refused before the stratagem is used.
			if t.has("secondary") and typeof(actx) == TYPE_DICTIONARY and typeof(t.get("secondary")) == TYPE_DICTIONARY \
					and not t.secondary.get("options", []).is_empty():
				var chosen_secondary := str(actx.get("secondary_id", ""))
				var secondary_ok := false
				for opt in t.secondary.get("options", []):
					if str(opt.get("id", "")) == chosen_secondary:
						secondary_ok = true
						break
				if not secondary_ok:
					return {"valid": false, "errors": ["%s: %s is not one of the offered choices" % [offer.get("name", sid), chosen_secondary]]}
			return {"valid": true, "errors": []}
		return {"valid": false, "errors": ["%s cannot target %s in this window" % [offer.get("name", sid), tid]]}
	return {"valid": false, "errors": ["%s is not offered in window %s" % [sid, window_id]]}

## The offered label of `variant_id` on (stratagem_id, target) in `offers`
## ("" when there is no variant or it is not in the offers).
func _window_variant_label(offers: Array, stratagem_id: String, target_unit_id: String, variant_id: String) -> String:
	if variant_id == "":
		return ""
	for offer in offers:
		if str(offer.get("stratagem_id", "")) != stratagem_id:
			continue
		for t in offer.get("targets", []):
			if str(t.get("unit_id", "")) != target_unit_id:
				continue
			for v in t.get("variants", []):
				if str(v.get("id", "")) == variant_id:
					return str(v.get("label", variant_id))
	return variant_id

func _process_window_action(action: Dictionary) -> Dictionary:
	var pending: Dictionary = _window_pending
	var player := int(pending.get("player", 0))
	var window_id := str(pending.get("window_id", ""))
	var diffs: Array = []
	var used := false
	var used_name := ""
	var katah_used := false
	if str(action.get("type", "")) == "USE_WINDOW_STRATAGEM":
		var use_res = _apply_window_use(player, window_id, str(action.get("stratagem_id", "")),
			str(action.get("target_unit_id", "")), action.get("context", {}), pending.get("ctx", {}), pending.get("offers", []))
		if not use_res.get("success", false):
			# Window stays open — the decider can pick something else or decline.
			return create_result(false, [], "Stratagem use failed: %s" % use_res.get("error", "?"))
		diffs.append_array(use_res.get("diffs", []))
		used = true
		used_name = str(use_res.get("stratagem_name", ""))
		katah_used = _cus11e_katah().is_katah_offer_id(str(action.get("stratagem_id", "")))
		log_phase_message("[StratagemWindow] P%d used %s on %s (%s)" % [player, used_name, action.get("target_unit_id", ""), window_id])
		# Codex: Orks (11e) free rule choice (WP-O34): re-offer the window for its stratagems.
		if use_res.get("reopen_window", false) and not _window_followup_pending:
			_window_queue.push_front({"player": player, "window_id": window_id, "ctx": pending.get("ctx", {})})
	else:
		_window_last_result = {"used": false, "player": player, "window_id": window_id}
		if bool(action.get("dont_offer_again", false)):
			_window_suppressed["%d:%s" % [player, window_id]] = true
			log_phase_message("[StratagemWindow] P%d declined %s — not offered again this phase" % [player, window_id])
		else:
			log_phase_message("[StratagemWindow] P%d declined %s" % [player, window_id])
	_window_pending = {}
	emit_signal("stratagem_window_closed", player, window_id, used)
	_window_event_closed(window_id, pending.get("ctx", {}), used)
	if used:
		# Codex: Adeptus Custodes (CustodesKatah.gd): a ka'tah use keeps the
		# window open with what is still offered; after a stratagem, a ka'tah
		# still usable in this window is offered next.
		_queue_katah_reopen(player, window_id, pending.get("ctx", {}), not katah_used)

	var result: Dictionary
	if _window_followup_pending:
		# The follow-up owns the phase now; _finish_window_followup() continues.
		result = create_result(true, diffs)
	else:
		result = _continue_window_queue_or_resume(diffs)
	result["stratagem_window_closed"] = {"player": player, "window_id": window_id, "used": used}
	result.merge(consume_window_result_extra(), false)
	if used:
		result["stratagem_used"] = {"stratagem_id": str(action.get("stratagem_id", "")), "stratagem_name": used_name,
			"target_unit_id": str(action.get("target_unit_id", "")), "player": player}
	return result

## Open the next queued window, or — when the queue is empty — call the
## phase's resume method and merge its result behind `diffs`.
func _continue_window_queue_or_resume(diffs: Array) -> Dictionary:
	# Units the answered window's stratagem destroyed / battle-shocked open
	# their own windows first (nested events, design §3) — then the queue.
	_window_events_detect()
	if _process_window_queue():
		var paused_diffs: Array = diffs.duplicate()
		paused_diffs.append_array(consume_window_diffs())
		return create_result(true, paused_diffs)
	var all_diffs: Array = diffs.duplicate()
	all_diffs.append_array(consume_window_diffs())
	var method := _window_resume_method
	var rctx := _window_resume_ctx
	_window_resume_method = ""
	_window_resume_ctx = {}
	if method == "":
		return create_result(true, all_diffs)
	if not has_method(method):
		_window_error("resume method %s() missing on %s" % [method, get_script().resource_path.get_file()])
		return create_result(true, all_diffs)
	var cont = call(method, rctx, _window_last_result)
	if typeof(cont) != TYPE_DICTIONARY:
		return create_result(true, all_diffs)
	if not cont.get("success", false):
		# Surface the resume failure but keep the window answer's diffs.
		_window_error("resume %s() failed: %s" % [method, cont.get("error", "?")])
		var failed = create_result(true, all_diffs)
		failed["resume_error"] = cont.get("error", "")
		return failed
	var combined_diffs: Array = all_diffs
	combined_diffs.append_array(cont.get("changes", []))
	var combined = create_result(true, combined_diffs)
	for key in cont:
		if key != "success" and key != "changes" and key != "phase" and key != "timestamp":
			combined[key] = cont[key]
	return combined

## A follow-up started by _execute_window_followup (that returned true) has
## finished: continue the window queue / resume the interrupted phase flow.
## Returns the result dictionary for the action that completed the follow-up.
func _finish_window_followup(diffs: Array = []) -> Dictionary:
	_window_followup_pending = false
	return _continue_window_queue_or_resume(diffs)

## Execute a follow-up returned by a stratagem handler (design §3.2). Phases
## that support follow-ups override this; return true when the follow-up
## pauses the phase (then call _finish_window_followup when it completes),
## false when it resolved immediately. The default refuses LOUDLY so a missing
## executor is a visible ERROR, never a silent no-op.
func _execute_window_followup(player: int, window_id: String, followup: Dictionary, _ctx: Dictionary) -> bool:
	_window_error("unsupported followup '%s' from window %s (P%d) in %s — no executor; effect skipped" % [
		str(followup.get("type", "?")), window_id, player, get_script().resource_path.get_file()])
	return false

## Follow-ups that need no phase-specific interaction run here, in every phase
## (design §3.2). Returns {handled: bool, diffs: Array (already applied)}.
func _execute_generic_window_followup(player: int, window_id: String, followup: Dictionary, _ctx: Dictionary) -> Dictionary:
	match str(followup.get("type", "")):
		"new_reserve_unit":
			var diffs := _followup_new_reserve_unit(player, followup)
			if not diffs.is_empty():
				PhaseManager.apply_state_changes(diffs)
			DebugLogger.info("[StratagemWindow] follow-up new_reserve_unit (%s, P%d) resolved: %d diff(s)" % [window_id, player, diffs.size()])
			return {"handled": true, "diffs": diffs}
		"ork11e_reoffer":
			# WP-O6 (OrkAbilities11e): a datasheet ability was used in a window that
			# can host several (Command phase heals, Makari's picks, ...) — open the
			# same window again with whatever is still on offer.
			_window_queue.push_front({"player": player, "window_id": window_id, "ctx": followup.get("ctx", {})})
			DebugLogger.info("[StratagemWindow] follow-up ork11e_reoffer: %s re-queued for P%d" % [window_id, player])
			return {"handled": true, "diffs": []}
	return {"handled": false, "diffs": []}

## new_reserve_unit {source_unit_id} (INFESTED WAR ZONE): add a NEW unit to
## `player`'s army identical to the (destroyed) source unit — same datasheet,
## wargear and meta — in Strategic Reserves, at its starting strength with
## full wounds. It gets a fresh unit id (the destroyed unit stays destroyed
## for scoring / kill tracking) and arrives through the normal reserves flow.
func _followup_new_reserve_unit(player: int, followup: Dictionary) -> Array:
	var src_id := str(followup.get("source_unit_id", ""))
	var src: Dictionary = GameState.get_unit(src_id)
	if src.is_empty():
		_window_error("new_reserve_unit: source unit '%s' not found — no unit added" % src_id)
		return []
	var units: Dictionary = GameState.state.get("units", {})
	var n := 2
	var new_id := "%s_R%d" % [src_id, n]
	while units.has(new_id):
		n += 1
		new_id = "%s_R%d" % [src_id, n]
	var unit: Dictionary = src.duplicate(true)
	unit["id"] = new_id
	unit["owner"] = player
	if unit.has("squad_id"):
		unit["squad_id"] = new_id
	unit["status"] = GameStateData.UnitStatus.IN_RESERVES
	unit["reserve_type"] = "strategic_reserves"
	unit["flags"] = {}
	unit["attached_to"] = null
	unit["attachment_data"] = {"attached_characters": []}
	unit["embarked_in"] = null
	unit["disembarked_this_phase"] = false
	var meta: Dictionary = unit.get("meta", {})
	var base_name := str(meta.get("display_name", meta.get("name", src_id)))
	meta["display_name"] = "%s #%d" % [base_name, n]
	unit["meta"] = meta
	var default_wounds = meta.get("stats", {}).get("wounds", 1)
	for m in unit.get("models", []):
		m["alive"] = true
		m["current_wounds"] = m.get("wounds", default_wounds)
		m["position"] = null
		m["status_effects"] = []
	DebugLogger.info("[StratagemWindow] new_reserve_unit: %s (%s) added to P%d's army in Strategic Reserves — %d model(s) at full wounds (copy of destroyed %s)" % [
		new_id, meta["display_name"], player, unit.get("models", []).size(), src_id])
	return [{"op": "set", "path": "units.%s" % new_id, "value": unit}]

# ----------------------------------------------------------------------------
# Cross-phase EVENT windows (design §3): unit_battle_shocked, unit_destroyed
# (before Deadly Demise), enemy_unit_has_attacked. Raised generically by
# comparing unit state before and after every action (and phase start), so
# every place a unit is destroyed or becomes battle-shocked — test, forced
# roll, emergency disembark, mortal wounds, attacks — opens its window without
# a per-site hook. Event windows are queued (_ev_deferred) and open as soon as
# nothing else is pending: at the end of the action, or when the current
# window / follow-up closes (nested events never deadlock or get lost).
# ----------------------------------------------------------------------------

## Unit whose attacks are being resolved right now (enemy_unit_has_attacked
## attribution). Shooting / Fight override with their active shooter/fighter.
func _window_attacking_unit_id() -> String:
	return ""

## Attacker of an action that resolves a whole attack in one go (Fire
## Overwatch, the atomic SHOOT) — nothing is "active" before or after it.
func _window_action_attacker_id(action: Dictionary) -> String:
	match str(action.get("type", "")):
		"USE_FIRE_OVERWATCH", "SHOOT":
			return str(action.get("unit_id", action.get("actor_unit_id", "")))
	return ""

func _ev_snapshot() -> Dictionary:
	var alive := {}
	var shocked := {}
	var units: Dictionary = GameState.state.get("units", {})
	for uid in units:
		var u = units[uid]
		if typeof(u) != TYPE_DICTIONARY or _is_unit_destroyed_check(u):
			continue
		alive[uid] = true
		if u.get("flags", {}).get("battle_shocked", false):
			shocked[uid] = true
	return {"alive": alive, "shocked": shocked}

## Save-resolution actions whose casualties the defender's save overlay
## (AllocationGroupOverlay 11e / WoundAllocationOverlay 10e) has ALREADY
## written into GameState before the action is sent (the overlay applies its
## batch on the defending peer, then Done sends the action with the same
## idempotent diffs).
const _EV_PREAPPLIED_ACTIONS: Array = ["APPLY_SAVES", "APPLY_MELEE_SAVES"]

## Outermost execute_action: fresh baseline + the action's attacker.
func _window_events_begin(action: Dictionary) -> void:
	_ev_depth += 1
	if _ev_depth != 1:
		return
	# Codex: Space Marines (11e) MORTIS SNARES (SMCodex11e.gd): settled positions before the action.
	_sm11e_codex().on_action_begin(str(action.get("type", "")))
	# An action that names its own attacker (atomic SHOOT, Fire Overwatch)
	# wins over the phase's selected unit: a unit can be selected (e.g. the
	# shooting panel's auto-selected shooter) while another unit's atomic
	# SHOOT resolves — its kills are that unit's attacks (framework F9).
	_ev_action_attacker = _window_action_attacker_id(action)
	if _ev_action_attacker == "":
		_ev_action_attacker = _window_attacking_unit_id()
	if str(action.get("type", "")) in _EV_PREAPPLIED_ACTIONS and not _ev_baseline.is_empty():
		# The overlay killed / battle-shocked units BETWEEN the previous action
		# and this one: compare against the previous action's baseline (credited
		# to this action's attacker) so their unit_destroyed /
		# enemy_unit_has_attacked windows are raised and Deadly Demise is held —
		# re-snapshotting first would hide those deaths (LIVE-1 / F2).
		# _window_events_detect() takes the fresh baseline itself.
		_window_events_detect()
		return
	_ev_baseline = _ev_snapshot()

## Compare unit state with the baseline and queue the event windows.
func _window_events_detect() -> void:
	if _ev_baseline.is_empty() or _is_network_client():
		# (F4: a network client raises no event windows — the host does.)
		_ev_baseline = _ev_snapshot()
		return
	var now := _ev_snapshot()
	var units: Dictionary = GameState.state.get("units", {})
	var attacker := _ev_action_attacker if _ev_action_attacker != "" else _window_attacking_unit_id()
	var attacker_owner := int(units.get(attacker, {}).get("owner", 0)) if attacker != "" else 0
	for uid in _ev_baseline.get("alive", {}):
		if now.alive.has(uid) or not units.has(uid):
			continue
		var owner := int(units[uid].get("owner", 0))
		# A unit whose destroyed models were only removed now (Fight On Death
		# keeps them until the unit has fought / the phase ends) is credited to
		# the enemy whose attacks destroyed them, not to whoever acts now.
		var unit_attacker := str(_ev_destroyed_by.get(uid, attacker))
		var unit_attacker_owner := attacker_owner
		if unit_attacker != attacker:
			unit_attacker_owner = int(units.get(unit_attacker, {}).get("owner", 0)) if unit_attacker != "" else 0
		var by_enemy := unit_attacker_owner != 0 and unit_attacker_owner != owner
		_ev_destroyed_open[uid] = true
		var ud_ctx := {"unit_id": uid, "attacker_unit_id": unit_attacker if by_enemy else ""}
		# Phases without their own kill pipeline (Movement, Charge, Command, ...)
		# resolve Deadly Demise here: held until the unit_destroyed window closes
		# (design §3 — the window opens BEFORE Deadly Demise), then
		# _window_event_closed -> _resolve_deadly_demise_if_applicable. Shooting
		# and Fight resolve it from their own _check_kill_diffs.
		if not _phase_resolves_deadly_demise() and _unit_has_deadly_demise(uid):
			_ev_dd_held[uid] = true
			ud_ctx["hold_deadly_demise"] = true
		_ev_deferred.append({"player": owner, "window_id": "unit_destroyed", "ctx": ud_ctx})
		DebugLogger.info("[StratagemWindow] event: %s destroyed (P%d)%s" % [uid, owner, (" by the attacks of %s" % unit_attacker) if by_enemy else ""])
		if by_enemy:
			if not _ev_attacks.has(unit_attacker):
				_ev_attacks[unit_attacker] = []
			_ev_attacks[unit_attacker].append(uid)
	_ev_destroyed_by.clear()
	var shocked_raised := {}
	for uid in now.get("shocked", {}):
		if _ev_baseline.get("shocked", {}).has(uid):
			continue
		# An Attached unit becomes battle-shocked as one unit: one window, keyed
		# by the unit its components resolve to.
		var head := str(RulesEngine.attached_unit_target_id(uid, GameState.state))
		if shocked_raised.has(head) or (head != uid and _ev_baseline.get("shocked", {}).has(head)):
			continue
		shocked_raised[head] = true
		var s_owner := int(units.get(head, {}).get("owner", 0))
		_ev_deferred.append({"player": s_owner, "window_id": "unit_battle_shocked", "ctx": {"unit_id": head}})
		DebugLogger.info("[StratagemWindow] event: %s became battle-shocked (P%d)" % [head, s_owner])
	_ev_baseline = now
	# An attacking unit whose attacks are over: enemy_unit_has_attacked for the
	# owner(s) of the units destroyed during those attacks.
	var still_attacking := _window_attacking_unit_id()
	for atk in _ev_attacks.keys():
		if atk == still_attacking:
			continue
		var by_owner := {}
		for d in _ev_attacks[atk]:
			var p := int(units.get(d, {}).get("owner", 0))
			if not by_owner.has(p):
				by_owner[p] = []
			by_owner[p].append(d)
		for p in by_owner:
			_ev_deferred.append({"player": p, "window_id": "enemy_unit_has_attacked",
				"ctx": {"attacker_unit_id": atk, "destroyed_unit_ids": by_owner[p]}})
			DebugLogger.info("[StratagemWindow] event: %s has attacked — destroyed %s (P%d)" % [atk, str(by_owner[p]), p])
		_ev_attacks.erase(atk)

## Move queued event windows to the FRONT of the window queue (they were
## caused by what just happened, so they resolve before older entries).
func _window_events_pull_deferred() -> void:
	if _ev_deferred.is_empty():
		return
	var entries: Array = _ev_deferred
	_ev_deferred = []
	entries.append_array(_window_queue)
	_window_queue = entries

## Detect events and open their windows if nothing else is pending. `result`
## (the action's result, or {}) receives the synchronous AI diffs and the
## stratagem_window_opened stamp for the network mirror.
func _window_events_flush(result) -> void:
	_window_events_detect()
	if _ev_deferred.is_empty():
		return
	var pm = get_node_or_null("/root/PhaseManager")
	if pm != null and pm.current_phase_instance != null and pm.current_phase_instance != self:
		# The action ended this phase: the windows open in the next phase.
		var nxt = pm.current_phase_instance
		var handed: Array = _ev_deferred
		_ev_deferred = []
		DebugLogger.info("[StratagemWindow] phase ended — handing %d event window(s) to %s" % [handed.size(), nxt.get_script().resource_path.get_file()])
		if nxt.has_method("_window_events_adopt"):
			nxt._window_events_adopt(handed)
			if typeof(result) == TYPE_DICTIONARY and nxt.has_pending_stratagem_window():
				result["stratagem_window_opened"] = nxt.get_pending_stratagem_window().duplicate(true)
		return
	if has_pending_stratagem_window() or _window_followup_pending:
		return  # opened by _continue_window_queue_or_resume when it closes
	var entries: Array = _ev_deferred
	_ev_deferred = []
	open_stratagem_windows(entries, "", {})
	var sync := consume_window_diffs()
	if typeof(result) != TYPE_DICTIONARY:
		return
	if not sync.is_empty():
		if result.get("changes", null) is Array:
			result.changes.append_array(sync)
		elif result.get("success", false):
			result["changes"] = sync
	if has_pending_stratagem_window():
		result["stratagem_window_opened"] = _window_pending.duplicate(true)

## Event windows handed over by the previous phase instance.
func _window_events_adopt(entries: Array) -> void:
	_ev_baseline = _ev_snapshot()
	for e in entries:
		if str(e.get("window_id", "")) == "unit_destroyed":
			var adopted_uid := str(e.get("ctx", {}).get("unit_id", ""))
			_ev_destroyed_open[adopted_uid] = true
			# A Deadly Demise held by the previous phase instance moves with
			# its window, so it still resolves when the window closes here.
			if bool(e.get("ctx", {}).get("hold_deadly_demise", false)):
				_ev_dd_held[adopted_uid] = true
	_ev_deferred.append_array(entries)
	_window_events_flush({})

## Called whenever a window closes (answered, declined, no offers, suppressed).
func _window_event_closed(window_id: String, ctx: Dictionary, used: bool) -> void:
	if window_id != "unit_destroyed":
		return
	var uid := str(ctx.get("unit_id", ""))
	_ev_destroyed_open.erase(uid)
	if _ev_dd_held.has(uid):
		_ev_dd_held.erase(uid)
		_ev_dd_released.append(uid)
		DebugLogger.info("[StratagemWindow] unit_destroyed window for %s closed (used=%s) — resolving its held Deadly Demise" % [uid, str(used)])
		if has_method("_resolve_deadly_demise_if_applicable"):
			call("_resolve_deadly_demise_if_applicable", uid)

## True for phases that resolve Deadly Demise from their own kill detection
## (ShootingPhase / FightPhase _check_kill_diffs). Every other phase relies on
## the generic event detection above (_window_events_detect).
func _phase_resolves_deadly_demise() -> bool:
	return false

func _unit_has_deadly_demise(unit_id: String) -> bool:
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr == null or not ability_mgr.has_deadly_demise(unit_id):
		return false
	# Only a unit destroyed ON the battlefield (e.g. not a reserve unit culled
	# at the end of round 3) has models whose Deadly Demise can hit anything.
	for m in GameState.get_unit(unit_id).get("models", []):
		if m.get("position", null) != null:
			return true
	return false

## Generic Deadly Demise resolution (phases without their own kill pipeline —
## a FLYIN' HEADBUTT or other mortal wounds in the Movement / Charge / Command
## phase used to destroy vehicles with no Deadly Demise roll at all).
## ShootingPhase and FightPhase override this with their own version.
func _resolve_deadly_demise_if_applicable(destroyed_unit_id: String) -> void:
	if _window_hold_deadly_demise(destroyed_unit_id):
		return
	var ability_mgr = get_node_or_null("/root/UnitAbilityManager")
	if ability_mgr == null or not ability_mgr.has_deadly_demise(destroyed_unit_id):
		return
	var dd_value = ability_mgr.get_deadly_demise_value(destroyed_unit_id)
	if dd_value == "":
		return
	var dd_meta = GameState.state.get("units", {}).get(destroyed_unit_id, {}).get("meta", {})
	var unit_name = dd_meta.get("display_name", dd_meta.get("name", destroyed_unit_id))
	DebugLogger.info(str("%s: Deadly Demise detected on destroyed unit %s (%s) — value: %s" % [get_script().resource_path.get_file(), unit_name, destroyed_unit_id, dd_value]))
	log_phase_message("Deadly Demise %s triggered for %s!" % [dd_value, unit_name])
	var dd_result = RulesEngine.resolve_deadly_demise(destroyed_unit_id, dd_value, GameState.state)
	if dd_result.get("triggered", false):
		var diffs = dd_result.get("diffs", [])
		if not diffs.is_empty():
			PhaseManager.apply_state_changes(diffs)
			log_phase_message("Deadly Demise %s: %d mortal wound(s) dealt to %d unit(s)" % [
				dd_value, dd_result.get("total_mortal_wounds", 0), dd_result.get("per_target", []).size()])
			# Units its mortal wounds destroyed raise their own windows (and
			# Deadly Demise) next.
			_window_events_detect()
			_window_events_pull_deferred()
	else:
		log_phase_message("Deadly Demise %s: roll of %d — did not trigger (needed 6)" % [
			dd_value, dd_result.get("trigger_roll", 0)])

## Deadly Demise sites call this first (design §3 unit_destroyed: the window
## opens BEFORE Deadly Demise is rolled). True = hold the roll until the
## unit's window closes (_window_event_closed resolves it then, unless a
## stratagem such as FLYIN' HEADBUTT removed the ability).
func _window_hold_deadly_demise(unit_id: String) -> bool:
	if _is_network_client():
		return false  # F4: the host holds (and resolves) Deadly Demise
	# Destroyed inside this very kill chain (e.g. by another unit's Deadly
	# Demise) and not detected yet: raise its unit_destroyed window now.
	if not _ev_destroyed_open.has(unit_id) and _ev_baseline.get("alive", {}).has(unit_id) \
			and _is_unit_destroyed_check(GameState.get_unit(unit_id)):
		_window_events_detect()
	if not _ev_destroyed_open.has(unit_id):
		return false
	# Only hold when the owner actually has something to offer — otherwise
	# Deadly Demise resolves exactly as before (same order, same dice).
	var owner := int(GameState.get_unit(unit_id).get("owner", 0))
	var dd_ctx := {"unit_id": unit_id, "phase": StratagemManager._phase_to_string(GameState.get_current_phase())}
	if StratagemManager.get_all_window_offers(owner, "unit_destroyed", dd_ctx).is_empty():
		return false
	_ev_dd_held[unit_id] = true
	DebugLogger.info("[StratagemWindow] Deadly Demise of %s held until its unit_destroyed window closes" % unit_id)
	return true

func _window_error(msg: String) -> void:
	push_error("[StratagemWindow] " + msg)
	DebugLogger.error("[StratagemWindow] " + msg, {})

## Networked CLIENT: mirror the host's pending window (NetworkManager calls
## this from the broadcast result) and re-emit the signal so Main shows the
## dialog on the decider's machine / the waiting overlay on the other.
func mirror_stratagem_window(window: Dictionary) -> void:
	_window_pending = window.duplicate(true)
	emit_signal("stratagem_window_opened", int(window.get("player", 0)), str(window.get("window_id", "")),
		window.get("offers", []), window.get("ctx", {}))

func clear_mirrored_stratagem_window() -> void:
	var player := int(_window_pending.get("player", 0))
	var window_id := str(_window_pending.get("window_id", ""))
	_window_pending = {}
	if window_id != "":
		emit_signal("stratagem_window_closed", player, window_id, false)
