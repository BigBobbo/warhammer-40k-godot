extends Node

## OWNERSHIP (ISS-025): PhaseManager owns the PHASE STATE MACHINE —
## creating/destroying phase instances, transitions, and the turn_ending
## hook pipeline (ISS-038). TurnManager owns TURN ORDER — alternation,
## roll-offs, and battle-round advancement — and only REQUESTS
## transitions. State mutation (the diff applier) is GameState's
## concern; apply_state_changes here is a compatibility forwarder.
const GameStateData = preload("res://autoloads/GameState.gd")
const BasePhase = preload("res://phases/BasePhase.gd")

# PhaseManager - Orchestrates phase transitions and manages the current active phase
# This is the central controller for the modular phase system

signal phase_changed(new_phase: GameStateData.Phase)
signal phase_completed(phase: GameStateData.Phase)
signal phase_action_taken(action: Dictionary)

# ── ISS-038: 11e battle-round / turn step events (core rules 07) ────
# Emitted at the structural seams so rules can hook the Start/End of Turn
# and Battle Round steps (coherency enforcement ISS-042, action completion
# ISS-057, battle-shock step wiring ISS-043, mission timing ISS-051/055).
signal turn_started(player: int)
signal turn_ending(player: int)
signal battle_round_started(round: int)
signal battle_round_ending(round: int)

var current_phase_instance: BasePhase = null
var phase_classes: Dictionary = {}
var game_ended: bool = false

# ISS-038: registered End of Turn hooks. Per 07.03 ordering, non-mission
# rules resolve before mission rules; registration order is preserved
# within each class. Hooks receive (player: int) and run BEFORE the
# player-switch diffs are built in ScoringPhase.
var _turn_ending_hooks: Array = []
var _hook_seq: int = 0
var _last_round_started: int = -1

func register_turn_ending_hook(cb: Callable, is_mission_rule: bool = false) -> void:
	_hook_seq += 1
	_turn_ending_hooks.append({"cb": cb, "mission": is_mission_rule, "order": _hook_seq})

func unregister_turn_ending_hook(cb: Callable) -> void:
	_turn_ending_hooks = _turn_ending_hooks.filter(func(h): return h.cb != cb)

func run_turn_ending_hooks(player: int) -> void:
	var hooks = _turn_ending_hooks.duplicate()
	hooks.sort_custom(func(a, b):
		if a.mission != b.mission:
			return not a.mission  # non-mission rules first (07.03)
		return a.order < b.order)
	for h in hooks:
		if h.cb.is_valid():
			h.cb.call(player)
	emit_signal("turn_ending", player)

func _ready() -> void:
	# Register all available phase classes
	register_phase_classes()

	# ISS-042 (11e 03.03 "Regaining Coherency"): in the End of Turn step,
	# units that are not in coherency must remove models until they are.
	# Removed models are destroyed but do NOT trigger on-death rules.
	# Registered as a non-mission End-of-Turn rule (07.03 ordering).
	register_turn_ending_hook(_enforce_coherency_11e, false)
	register_turn_ending_hook(_complete_actions_11e, false)

	# Don't automatically start deployment phase here
	# Let the Main scene initialize it after armies are loaded
	print("[PhaseManager] Ready - awaiting explicit phase initialization")

func reset() -> void:
	# Clean up current phase instance when returning to main menu
	# PhaseManager is an autoload so it persists across scene changes
	print("[PhaseManager] Resetting state for new game")
	if current_phase_instance != null:
		current_phase_instance.exit_phase()
		current_phase_instance.queue_free()
		current_phase_instance = null
	game_ended = false

func register_phase_classes() -> void:
	# Register phase implementations
	phase_classes[GameStateData.Phase.FORMATIONS] = preload("res://phases/FormationsPhase.gd")
	phase_classes[GameStateData.Phase.DEPLOYMENT] = preload("res://phases/DeploymentPhase.gd")
	phase_classes[GameStateData.Phase.REDEPLOYMENT] = preload("res://phases/RedeploymentPhase.gd")
	phase_classes[GameStateData.Phase.SCOUT] = preload("res://phases/ScoutPhase.gd")
	phase_classes[GameStateData.Phase.ROLL_OFF] = preload("res://phases/RollOffPhase.gd")
	phase_classes[GameStateData.Phase.FIRST_TURN_ROLLOFF] = preload("res://phases/FirstTurnRollOffPhase.gd")
	phase_classes[GameStateData.Phase.COMMAND] = preload("res://phases/CommandPhase.gd")
	phase_classes[GameStateData.Phase.MOVEMENT] = preload("res://phases/MovementPhase.gd")
	phase_classes[GameStateData.Phase.SHOOTING] = preload("res://phases/ShootingPhase.gd")
	phase_classes[GameStateData.Phase.CHARGE] = preload("res://phases/ChargePhase.gd")
	phase_classes[GameStateData.Phase.FIGHT] = preload("res://phases/FightPhase.gd")
	phase_classes[GameStateData.Phase.SCORING] = preload("res://phases/ScoringPhase.gd")

func transition_to_phase(new_phase: GameStateData.Phase) -> void:
	# ISS-034: SCOUT_MOVES and MORALE are deprecated phases (scout moves run
	# through SCOUT; battle-shock lives in COMMAND per 10e/11e). Their enum
	# slots are kept so saved phase ints stay valid; transitions remap.
	if new_phase == GameStateData.Phase.SCOUT_MOVES or new_phase == GameStateData.Phase.MORALE:
		print("[PhaseManager] Deprecated phase %s requested — remapping to COMMAND (ISS-034)" % GameStateData.Phase.keys()[new_phase])
		new_phase = GameStateData.Phase.COMMAND
	print("[PhaseManager] transition_to_phase called for: ", GameStateData.Phase.keys()[new_phase])

	# Clear sticky end-of-game flag when starting a new game.
	# `game_ended` is set in `_handle_game_end` and would otherwise survive
	# `GameState.initialize_default_state` (which only resets `state`, not autoload
	# member fields), blocking all phase advancement in the new game. See issue #330.
	if new_phase == GameStateData.Phase.FORMATIONS:
		game_ended = false

	# Exit current phase if one exists
	if current_phase_instance != null:
		print("[PhaseManager] Exiting current phase: ", current_phase_instance.get_class())
		# Sever signals BEFORE queue_free: the node stays alive until end of
		# frame, so a deferred phase_completed from the outgoing instance (e.g.
		# RedeploymentPhase's auto-skip call_deferred) would otherwise fire
		# _on_phase_completed against the NEW phase and silently skip it.
		# This is how FIRST_TURN_ROLLOFF got skipped in multiplayer games.
		if current_phase_instance.has_signal("phase_completed") and current_phase_instance.phase_completed.is_connected(_on_phase_completed):
			current_phase_instance.phase_completed.disconnect(_on_phase_completed)
		if current_phase_instance.has_signal("action_taken") and current_phase_instance.action_taken.is_connected(_on_phase_action_taken):
			current_phase_instance.action_taken.disconnect(_on_phase_action_taken)
		current_phase_instance.exit_phase()
		current_phase_instance.queue_free()
		current_phase_instance = null

		# SUPERIOR CREATION (Lions of the Emperor enhancement): bearers destroyed
		# during the outgoing phase roll their 2+ revival now — "at the end of
		# the phase" — before the next phase begins.
		# Multiplayer: HOST-only. transition_to_phase runs on both peers, and
		# each rolled its own unseeded d6 here (client make_rng falls back to
		# randomize()) — divergent revival results that were never broadcast.
		# The host now rolls once and ships the diffs to the client.
		var sc_networked = NetworkManager.is_networked()
		if not sc_networked or NetworkManager.is_host():
			var sc_result = RulesEngine.resolve_superior_creation_revivals(GameState.state)
			if not sc_result.get("diffs", []).is_empty():
				apply_state_changes(sc_result.diffs)
				if sc_networked:
					NetworkManager._broadcast_result_from_phase_manager({
						"success": true,
						"diffs": sc_result.diffs,
						"action_type": "SUPERIOR_CREATION_REVIVAL"
					})
			for sc_line in sc_result.get("log_lines", []):
				print("[PhaseManager] %s" % sc_line)

	# Update game state to new phase
	GameState.set_phase(new_phase)

	# MULTIPLAYER FIX: Broadcast phase change to all clients
	if NetworkManager.is_networked() and NetworkManager.is_host():
		print("[PhaseManager] Broadcasting phase change to clients: ", GameStateData.Phase.keys()[new_phase])
		NetworkManager.broadcast_phase_change(new_phase)

	# Create and initialize new phase instance
	if phase_classes.has(new_phase):
		print("[PhaseManager] Creating new phase instance for: ", GameStateData.Phase.keys()[new_phase])
		var phase_script = phase_classes[new_phase]
		print("[PhaseManager] Phase script: ", phase_script)

		# Create node and attach script
		var phase_node = Node.new()
		phase_node.set_script(phase_script)
		current_phase_instance = phase_node as BasePhase

		print("[PhaseManager] Created instance class: ", current_phase_instance.get_class())
		print("[PhaseManager] Instance script: ", current_phase_instance.get_script())
		print("[PhaseManager] Instance has validate_action: ", current_phase_instance.has_method("validate_action"))
		add_child(current_phase_instance)
		
		# Connect phase signals
		if current_phase_instance.has_signal("phase_completed"):
			current_phase_instance.phase_completed.connect(_on_phase_completed)
			print("[PhaseManager] Connected to phase_completed signal")
		else:
			print("[PhaseManager] WARNING: No phase_completed signal")
		if current_phase_instance.has_signal("action_taken"):
			current_phase_instance.action_taken.connect(_on_phase_action_taken)
			print("[PhaseManager] Connected to action_taken signal")
		else:
			print("[PhaseManager] WARNING: No action_taken signal")
		
		# Enter the new phase
		var snapshot = GameState.create_snapshot()
		print("[PhaseManager] Creating snapshot for phase ", new_phase)
		print("[PhaseManager] Snapshot has ", snapshot.get("units", {}).size(), " units")
		if snapshot.has("units") and snapshot.units.size() > 0:
			print("[PhaseManager] Unit IDs: ", snapshot.units.keys())

		current_phase_instance.enter_phase(snapshot)

		# ISS-038: a player turn begins with its Command phase (07.02).
		if new_phase == GameStateData.Phase.COMMAND:
			var round_now = GameState.get_battle_round()
			if round_now != _last_round_started:
				_last_round_started = round_now
				emit_signal("battle_round_started", round_now)
			emit_signal("turn_started", GameState.get_active_player())

		emit_signal("phase_changed", new_phase)
	else:
		push_error("No implementation found for phase: " + str(new_phase))

func get_current_phase() -> GameStateData.Phase:
	return GameState.get_current_phase()

func get_current_phase_instance() -> BasePhase:
	if current_phase_instance:
		print("[PhaseManager] get_current_phase_instance returning: ", current_phase_instance.get_class())
		print("[PhaseManager] Instance script path: ", current_phase_instance.get_script().resource_path if current_phase_instance.get_script() else "no script")
		print("[PhaseManager] Instance has validate_action: ", current_phase_instance.has_method("validate_action"))

		# Check if this is actually a DeploymentPhase
		var script = current_phase_instance.get_script()
		if script:
			var script_path = script.resource_path
			print("[PhaseManager] ⚠️ Script path: ", script_path)
			if "Deployment" in script_path:
				print("[PhaseManager] ⚠️ This SHOULD be a DeploymentPhase!")
	else:
		print("[PhaseManager] get_current_phase_instance returning: null")
	return current_phase_instance

func advance_to_next_phase() -> void:
	print("PhaseManager: advance_to_next_phase() called")
	var current = get_current_phase()
	var next_phase = _get_next_phase(current)
	print("PhaseManager: current=", GameStateData.Phase.keys()[current], " next=", GameStateData.Phase.keys()[next_phase])

	# MULTIPLAYER FIX: When phase advances automatically (auto-complete),
	# we need to sync this with clients via NetworkManager
	var network_mgr = get_node_or_null("/root/NetworkManager")
	var is_networked = network_mgr and network_mgr.is_networked()
	var is_host = network_mgr and network_mgr.is_host()
	print("PhaseManager: is_networked=", is_networked, " is_host=", is_host)

	if next_phase != current:
		# Normal phase advance
		if is_networked and is_host:
			# Host: broadcast phase change to clients via a state diff
			print("PhaseManager: Host broadcasting auto phase change: ", GameStateData.Phase.keys()[current], " -> ", GameStateData.Phase.keys()[next_phase])
			var result = {
				"success": true,
				"diffs": [{
					"op": "set",
					"path": "meta.phase",
					"value": next_phase
				},
				# The phase advance happens INSIDE the action apply on the host,
				# so this broadcast reaches the client BEFORE the action result
				# that changed active_player/battle_round (END_TURN). Without
				# these, the client transitioned into the new phase with the
				# STALE active player and ran the wrong player's phase-entry
				# bookkeeping (observed: client entered COMMAND as P1 on P2's
				# turn — wrong deck draws, missing detachment flags, desync).
				{
					"op": "set",
					"path": "meta.active_player",
					"value": GameState.get_active_player()
				},
				{
					"op": "set",
					"path": "meta.battle_round",
					"value": GameState.get_battle_round()
				}],
				"action_type": "AUTO_PHASE_ADVANCE",
				"action_data": {
					"type": "AUTO_PHASE_ADVANCE",
					"from_phase": current,
					"to_phase": next_phase
				}
			}
			# Apply locally first
			GameState.set_phase(next_phase)
			# Then broadcast to clients
			network_mgr._broadcast_result_from_phase_manager(result)

		transition_to_phase(next_phase)
	else:
		# End of turn, advance turn and start with deployment
		GameState.advance_turn()

		if is_networked and is_host:
			# Broadcast turn advance and phase reset
			print("PhaseManager: Host broadcasting turn advance and phase reset")
			var result = {
				"success": true,
				"diffs": [
					{"op": "set", "path": "meta.turn_number", "value": GameState.get_turn_number()},
					{"op": "set", "path": "meta.phase", "value": GameStateData.Phase.DEPLOYMENT}
				],
				"action_type": "AUTO_TURN_ADVANCE"
			}
			network_mgr._broadcast_result_from_phase_manager(result)

		transition_to_phase(GameStateData.Phase.DEPLOYMENT)

func _get_next_phase(current: GameStateData.Phase) -> GameStateData.Phase:
	# Define the standard 40k phase order with Command and Scoring phases.
	#
	# Issue #85: per Chapter Approved 2025-26 + the current 10e core rules,
	# the pre-deployment roll-off determines the attacker / defender (and
	# therefore who deploys first). Previously ROLL_OFF ran after
	# REDEPLOYMENT — but that left issue #377's defender-first logic
	# (TurnManager._handle_deployment_phase_start reads meta.defender) with
	# no value to read, because meta.defender wasn't set until after
	# deployment was already done. Moving ROLL_OFF to between FORMATIONS
	# and DEPLOYMENT activates that path.
	#
	# Scout moves happen before the first Command phase, after deployment +
	# redeployment.
	match current:
		GameStateData.Phase.FORMATIONS:
			return GameStateData.Phase.ROLL_OFF
		GameStateData.Phase.ROLL_OFF:
			return GameStateData.Phase.DEPLOYMENT
		GameStateData.Phase.DEPLOYMENT:
			return GameStateData.Phase.REDEPLOYMENT
		GameStateData.Phase.REDEPLOYMENT:
			# 10e: after armies are deployed (and redeployment abilities resolved),
			# the separate "Determine First Turn" roll-off happens, then Scout moves.
			return GameStateData.Phase.FIRST_TURN_ROLLOFF
		GameStateData.Phase.FIRST_TURN_ROLLOFF:
			return GameStateData.Phase.SCOUT
		GameStateData.Phase.SCOUT:
			return GameStateData.Phase.COMMAND
		# SCOUT_MOVES is not part of the standard phase chain (SCOUT -> COMMAND).
		# It is only reachable via direct transition_to_phase() calls (e.g. from
		# MCP execute_script or test harnesses). Kept here so that auto-advance
		# from a manually-entered SCOUT_MOVES phase still routes to COMMAND.
		# See issue #332.
		GameStateData.Phase.SCOUT_MOVES:
			return GameStateData.Phase.COMMAND
		GameStateData.Phase.COMMAND:
			return GameStateData.Phase.MOVEMENT
		GameStateData.Phase.MOVEMENT:
			return GameStateData.Phase.SHOOTING
		GameStateData.Phase.SHOOTING:
			return GameStateData.Phase.CHARGE
		GameStateData.Phase.CHARGE:
			return GameStateData.Phase.FIGHT
		GameStateData.Phase.FIGHT:
			return GameStateData.Phase.SCORING
		GameStateData.Phase.SCORING:
			# After scoring, player switching already happened in ScoringPhase
			var current_player = GameState.get_active_player()
			var battle_round = GameState.get_battle_round()
			
			print("PhaseManager: After scoring, current player is ", current_player, ", battle round is ", battle_round)
			
			# If current_player == 2, Player 1 just finished their turn -> Player 2's turn starts
			# If current_player == 1, Player 2 just finished their turn -> new battle round for Player 1
			
			# Always go to COMMAND phase for the next player (deployment only happens once at game start)
			return GameStateData.Phase.COMMAND
		# TODO: deprecate, MORALE is not a 10e phase (battle-shock happens in
		# the Command phase). MoralePhase.gd is retained for legacy/test paths.
		# Fallback routes to COMMAND so that a stray MORALE transition does not
		# kick the game back to DEPLOYMENT mid-game. See issue #332.
		GameStateData.Phase.MORALE:
			return GameStateData.Phase.COMMAND
		_:
			return GameStateData.Phase.DEPLOYMENT

func _on_phase_completed() -> void:
	if game_ended:
		return

	# Multiplayer: only the HOST advances phases. A phase instance on a client
	# can auto-complete locally (Redeployment/Scout with nothing to do) but the
	# client must wait for the host's phase-change RPC / broadcast diffs —
	# otherwise the client free-runs ahead of the host (observed: client raced
	# through COMMAND→MOVEMENT→SHOOTING→CHARGE while the host sat in SCOUT).
	var network_mgr = get_node_or_null("/root/NetworkManager")
	if network_mgr and network_mgr.is_networked() and not network_mgr.is_host():
		print("PhaseManager: phase_completed on CLIENT — waiting for host to advance")
		return

	var completed_phase = get_current_phase()

	# Check for game end before advancing
	if completed_phase == GameStateData.Phase.SCORING and GameState.is_game_complete():
		_handle_game_end()
		return

	# Commit current phase log to history before transitioning
	GameState.commit_phase_log_to_history()

	emit_signal("phase_completed", completed_phase)

	# Advance to next phase
	advance_to_next_phase()

func _handle_game_end() -> void:
	print("PhaseManager: Game completed after 5 battle rounds!")
	print("PhaseManager: Final battle round: ", GameState.get_battle_round())

	# Score end-of-game burn bonuses for Scorched Earth before marking game ended.
	# Idempotent: ScoringPhase calls this first when it detects the final-turn end,
	# but trigger again here for paths that reach _handle_game_end without it.
	if MissionManager:
		MissionManager.score_end_of_game_burn_bonus()
		# 11e GDM primary missions: end-of-game conditions (idempotent guard
		# inside — ScoringPhase._handle_game_end_turn usually fires first).
		if GameConstants.edition >= 11:
			MissionManager.score_primary_eog_11e()

	game_ended = true

	# Persist end-of-game flags to state so saves/replays/MCP queries observe them.
	# ISS-001: applied through the diff pipeline so replay/undo/network record it.
	if not GameState.state.get("meta", {}).get("game_ended", false):
		apply_state_changes([
			{"op": "set", "path": "meta.game_ended", "value": true},
			{"op": "set", "path": "meta.winner", "value": _determine_vp_winner()}
		])

	# Commit final phase log
	GameState.commit_phase_log_to_history()

	# Emit completion signal for any listeners that need to know the game ended
	emit_signal("phase_completed", GameStateData.Phase.SCORING)

func _determine_vp_winner() -> int:
	if not MissionManager or not MissionManager.has_method("get_vp_summary"):
		return 0
	var vp = MissionManager.get_vp_summary()
	var p1 = int(vp.get("player1", {}).get("total", 0))
	var p2 = int(vp.get("player2", {}).get("total", 0))
	if p1 > p2:
		return 1
	if p2 > p1:
		return 2
	return 0

func _on_phase_action_taken(action: Dictionary) -> void:
	if game_ended:
		return

	# Record action in phase log
	GameState.add_action_to_phase_log(action)

	emit_signal("phase_action_taken", action)

# Utility methods for phases to interact with game state
func get_game_state_snapshot() -> Dictionary:
	return GameState.create_snapshot()

## ISS-025: the diff applier lives in GameState (state's concern).
## PhaseManager forwards for the existing call sites; new code should
## call GameState.apply_state_changes directly.
func apply_state_changes(changes: Array) -> void:
	GameState.apply_state_changes(changes)

# Method for phases to validate their actions
func validate_phase_action(action: Dictionary) -> Dictionary:
	if current_phase_instance and current_phase_instance.has_method("validate_action"):
		return current_phase_instance.validate_action(action)
	else:
		return {"valid": true, "errors": []}

# Method to get available actions for current phase
func get_available_actions() -> Array:
	if current_phase_instance and current_phase_instance.has_method("get_available_actions"):
		return current_phase_instance.get_available_actions()
	else:
		return []


## ISS-057 step 2: actions that complete at the end of the turn resolve
## through the ISS-038 hook (16.01; battle-shock blocks completion per
## 01.07 — handled inside ActionsManager.complete_actions).
func _complete_actions_11e(_player: int) -> void:
	if GameConstants.edition < 11:
		return
	var result = ActionsManager.complete_actions("end_of_turn", GameState.state)
	if not result.changes.is_empty():
		apply_state_changes(result.changes)
	for c in result.completed:
		print("PhaseManager: [11e ACTIONS] %s completed action '%s' (effect: %s)" % [c.unit_id, c.action_id, str(c.effect)])
		# Mission-card actions (Sabotage / Vanguard Operation / Extract
		# Intelligence) resolve their scoring state in MissionManager.
		if str(c.effect).begins_with("mission:") and MissionManager.has_method("on_mission_action_completed_11e"):
			MissionManager.on_mission_action_completed_11e(c.unit_id, str(c.effect))


## ISS-042: 11e end-of-turn coherency enforcement. Auto-removes detected
## offender models (the owning player's pick UI arrives with the 11e
## scenario suite, ISS-063); diffs go through the pipeline so replay/
## network observe the removals. No on-death triggers fire by design.
func _enforce_coherency_11e(_player: int) -> void:
	if GameConstants.edition < 11:
		return
	var units = GameState.state.get("units", {})
	for unit_id in units:
		var unit = units[unit_id]
		var alive := 0
		for m in unit.get("models", []):
			if m.get("alive", true) and m.get("position") != null:
				alive += 1
		if alive <= 1:
			continue
		var removed: Array = []
		# Remove offenders one at a time, rechecking, until coherent
		# (capped at the model count to guarantee termination). The player
		# may choose which models to remove (03.03); the auto-pick removes
		# the MOST ISOLATED offender (greatest total distance to the rest),
		# which preserves the largest coherent group.
		for _i in range(unit.get("models", []).size()):
			var coh = AttackSequence.check_unit_coherency(unit)
			if coh.coherent:
				break
			var offender_id = _most_isolated_offender(unit, coh.offenders)
			var changes: Array = []
			for mi in range(unit.models.size()):
				if str(unit.models[mi].get("id", mi)) == str(offender_id):
					changes.append({"op": "set", "path": StateSchema.path_model_field(unit_id, mi, "alive"), "value": false})
					changes.append({"op": "set", "path": StateSchema.path_model_field(unit_id, mi, "current_wounds"), "value": 0})
					break
			if changes.is_empty():
				break
			apply_state_changes(changes)
			removed.append(offender_id)
		if not removed.is_empty():
			print("[PhaseManager] ISS-042: %s out of coherency at End of Turn — removed %s (destroyed, no on-death triggers per 03.03)" % [unit_id, str(removed)])


func _most_isolated_offender(unit: Dictionary, offenders: Array) -> String:
	var models: Array = unit.get("models", [])
	var best_id := str(offenders[0])
	var best_score := -1.0
	for oid in offenders:
		var om = null
		for m in models:
			if str(m.get("id", "")) == str(oid):
				om = m
				break
		if om == null:
			continue
		var total := 0.0
		for m in models:
			if not m.get("alive", true) or str(m.get("id", "")) == str(oid):
				continue
			total += Measurement.model_to_model_distance_px(om, m)
		if total > best_score:
			best_score = total
			best_id = str(oid)
	return best_id
