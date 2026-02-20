extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# AIPlayer - Autoload controller for AI opponents
# Monitors game signals and submits actions through NetworkIntegration.route_action()
# when the active player is configured as AI.
#
# Handles both active-turn decisions (via _evaluate_and_act) and reactive stratagem
# decisions (via phase signal connections) for stratagems like Fire Overwatch,
# Go to Ground, Smokescreen, and Command Re-roll.

# Configuration
var ai_players: Dictionary = {}  # player_id (int) -> true/false (is AI)
var enabled: bool = false
var _processing_turn: bool = false  # Guard against re-entrant calls
var _action_log: Array = []  # Log of AI actions for summary display
var _current_phase_actions: int = 0  # Safety counter per phase
const MAX_ACTIONS_PER_PHASE: int = 200  # Safety limit to prevent infinite loops

# Frame-paced evaluation: ensures the renderer gets to draw between AI actions
var _needs_evaluation: bool = false
var _eval_timer: float = 0.0
const AI_ACTION_DELAY: float = 0.05  # 50ms between actions so UI can update

# T7-20: AI thinking state — tracks whether the AI is actively processing its turn
var _ai_thinking: bool = false

# Cached reference to PhaseManager (get_node_or_null fails in web exports)
var _phase_manager_ref: Node = null

# Track connected phase signals for cleanup on phase transition
var _connected_phase_signals: Array = []  # [{signal_name, callable}]
var _current_phase_ref = null  # Reference to the currently connected phase instance

# Signals for UI
signal ai_turn_started(player: int)
signal ai_turn_ended(player: int, action_summary: Array)
signal ai_action_taken(player: int, action: Dictionary, description: String)
signal ai_unit_deployed(player: int, unit_id: String)

func _ready() -> void:
	# Connect to signals - use call_deferred to avoid acting during signal emission
	if has_node("/root/GameManager"):
		var game_manager = get_node("/root/GameManager")
		game_manager.result_applied.connect(_on_result_applied)
		print("AIPlayer: Connected to GameManager.result_applied")
	else:
		push_warning("AIPlayer: GameManager not found at startup")

	if has_node("/root/PhaseManager"):
		_phase_manager_ref = get_node("/root/PhaseManager")
		var phase_manager = _phase_manager_ref
		phase_manager.phase_changed.connect(_on_phase_changed)
		# phase_action_taken fires after every action in single-player mode,
		# which is critical because NetworkIntegration.route_action bypasses
		# GameManager (and thus result_applied) when not in multiplayer.
		phase_manager.phase_action_taken.connect(_on_phase_action_taken)
		print("AIPlayer: Connected to PhaseManager.phase_changed and phase_action_taken")
	else:
		push_warning("AIPlayer: PhaseManager not found at startup")

	set_process(true)
	print("AIPlayer: Ready (disabled until configured)")

func _process(delta: float) -> void:
	if not _needs_evaluation or not enabled or PhaseManager.game_ended or _processing_turn:
		return
	_eval_timer -= delta
	if _eval_timer <= 0.0:
		_needs_evaluation = false
		_evaluate_and_act()

func _request_evaluation() -> void:
	"""Schedule an AI evaluation for the next frame(s), giving the renderer time to draw."""
	_needs_evaluation = true
	_eval_timer = AI_ACTION_DELAY

	# T7-20: Signal that AI is now thinking (only on first evaluation of a sequence)
	if not _ai_thinking:
		var active_player = GameState.get_active_player()
		if is_ai_player(active_player):
			_ai_thinking = true
			emit_signal("ai_turn_started", active_player)
			print("AIPlayer: AI thinking started for player %d" % active_player)

func _end_ai_thinking() -> void:
	"""T7-20: Signal that the AI has finished its current thinking sequence."""
	if _ai_thinking:
		_ai_thinking = false
		var active_player = GameState.get_active_player()
		emit_signal("ai_turn_ended", active_player, _action_log.duplicate())
		print("AIPlayer: AI thinking ended for player %d" % active_player)

func configure(player_types: Dictionary) -> void:
	"""
	Called from Main.gd during initialization.
	player_types: {1: "HUMAN" or "AI", 2: "HUMAN" or "AI"}
	"""
	ai_players.clear()
	_action_log.clear()
	_current_phase_actions = 0

	for player_id in player_types:
		ai_players[int(player_id)] = (player_types[player_id] == "AI")
	enabled = ai_players.values().has(true)

	print("AIPlayer: Configured - P1=%s, P2=%s, enabled=%s" % [
		player_types.get(1, player_types.get("1", "HUMAN")),
		player_types.get(2, player_types.get("2", "HUMAN")),
		enabled])

	# If AI should act right away (e.g., Player 1 is AI in deployment), kick off
	if enabled:
		_request_evaluation()

func is_ai_player(player: int) -> bool:
	return enabled and ai_players.get(player, false)

func get_action_log() -> Array:
	return _action_log.duplicate()

func clear_action_log() -> void:
	_action_log.clear()

# --- Signal handlers ---

func _on_phase_changed(_new_phase) -> void:
	if not enabled or PhaseManager.game_ended:
		return
	_current_phase_actions = 0  # Reset safety counter on phase change

	# T7-20: End any active thinking state before starting a new phase evaluation
	_end_ai_thinking()

	# Connect to reactive stratagem signals on the new phase instance
	_connect_phase_stratagem_signals()

	_request_evaluation()

func _on_result_applied(_result: Dictionary) -> void:
	if not enabled or PhaseManager.game_ended:
		return
	# After any action result, check if AI should act next
	_request_evaluation()

func _on_phase_action_taken(_action: Dictionary) -> void:
	if not enabled or PhaseManager.game_ended:
		return
	# After any phase action, check if AI should act next
	# This is the primary trigger in single-player mode
	DebugLogger.info("AIPlayer._on_phase_action_taken - scheduling evaluation", {"action_type": _action.get("type", "?"), "enabled": enabled})
	_request_evaluation()

# =============================================================================
# REACTIVE STRATAGEM SIGNAL HANDLING
# =============================================================================

func _connect_phase_stratagem_signals() -> void:
	"""
	Connect to stratagem-related signals on the current phase instance.
	This allows the AI to respond to reactive stratagem opportunities that
	fire during the opponent's turn (e.g., Fire Overwatch, Go to Ground).
	"""
	# Disconnect any previously connected signals
	_disconnect_phase_stratagem_signals()

	if not _phase_manager_ref:
		_phase_manager_ref = get_node_or_null("/root/PhaseManager")
	if not _phase_manager_ref:
		return

	var phase = _phase_manager_ref.current_phase_instance
	if not phase:
		return

	_current_phase_ref = phase

	# --- ShootingPhase signals ---
	if phase.has_signal("reactive_stratagem_opportunity"):
		var callable = Callable(self, "_on_reactive_stratagem_opportunity")
		phase.reactive_stratagem_opportunity.connect(callable)
		_connected_phase_signals.append({"signal_name": "reactive_stratagem_opportunity", "callable": callable})
		print("AIPlayer: Connected to ShootingPhase.reactive_stratagem_opportunity")

	# --- MovementPhase signals ---
	if phase.has_signal("fire_overwatch_opportunity"):
		var callable = Callable(self, "_on_movement_fire_overwatch_opportunity")
		phase.fire_overwatch_opportunity.connect(callable)
		_connected_phase_signals.append({"signal_name": "fire_overwatch_opportunity", "callable": callable})
		print("AIPlayer: Connected to MovementPhase.fire_overwatch_opportunity")

	if phase.has_signal("command_reroll_opportunity"):
		var callable = Callable(self, "_on_command_reroll_opportunity")
		phase.command_reroll_opportunity.connect(callable)
		_connected_phase_signals.append({"signal_name": "command_reroll_opportunity", "callable": callable})
		print("AIPlayer: Connected to phase.command_reroll_opportunity")

	# --- ChargePhase signals ---
	# Note: ChargePhase overwatch and reroll actions are exposed via get_available_actions()
	# so they are handled by _decide_charge() in AIDecisionMaker. But the charge phase also
	# emits signals, so we connect for the reroll context data.
	if phase.has_signal("overwatch_opportunity"):
		var callable = Callable(self, "_on_charge_overwatch_opportunity")
		phase.overwatch_opportunity.connect(callable)
		_connected_phase_signals.append({"signal_name": "overwatch_opportunity", "callable": callable})
		print("AIPlayer: Connected to ChargePhase.overwatch_opportunity")

	# Tank Shock and Heroic Intervention are handled via get_available_actions()
	# in _decide_charge(), but we also connect signals to trigger re-evaluation promptly.
	if phase.has_signal("tank_shock_opportunity"):
		var callable = Callable(self, "_on_tank_shock_opportunity")
		phase.tank_shock_opportunity.connect(callable)
		_connected_phase_signals.append({"signal_name": "tank_shock_opportunity", "callable": callable})
		print("AIPlayer: Connected to ChargePhase.tank_shock_opportunity")

	if phase.has_signal("heroic_intervention_opportunity"):
		var callable = Callable(self, "_on_heroic_intervention_opportunity")
		phase.heroic_intervention_opportunity.connect(callable)
		_connected_phase_signals.append({"signal_name": "heroic_intervention_opportunity", "callable": callable})
		print("AIPlayer: Connected to ChargePhase.heroic_intervention_opportunity")

	# T7-32: Counter-Offensive in Fight Phase
	if phase.has_signal("counter_offensive_opportunity"):
		var callable = Callable(self, "_on_counter_offensive_opportunity")
		phase.counter_offensive_opportunity.connect(callable)
		_connected_phase_signals.append({"signal_name": "counter_offensive_opportunity", "callable": callable})
		print("AIPlayer: Connected to FightPhase.counter_offensive_opportunity")

func _disconnect_phase_stratagem_signals() -> void:
	"""Disconnect all previously connected phase stratagem signals."""
	if _current_phase_ref and is_instance_valid(_current_phase_ref):
		for entry in _connected_phase_signals:
			var signal_name = entry.get("signal_name", "")
			var callable = entry.get("callable", Callable())
			if _current_phase_ref.has_signal(signal_name) and _current_phase_ref.is_connected(signal_name, callable):
				_current_phase_ref.disconnect(signal_name, callable)
	_connected_phase_signals.clear()
	_current_phase_ref = null

# --- Reactive Stratagem: Go to Ground / Smokescreen (ShootingPhase) ---

func _on_reactive_stratagem_opportunity(defending_player: int, available_stratagems: Array, target_unit_ids: Array) -> void:
	"""
	Called when the ShootingPhase offers reactive stratagems (Go to Ground / Smokescreen)
	to the defending player. If the defender is AI, evaluate and submit a decision.
	"""
	if not is_ai_player(defending_player):
		return  # Not our AI — let human handle it

	print("AIPlayer: Reactive stratagem opportunity for AI player %d (stratagems: %d, targets: %d)" % [
		defending_player, available_stratagems.size(), target_unit_ids.size()])

	var snapshot = GameState.create_snapshot()
	var decision = AIDecisionMaker.evaluate_reactive_stratagem(
		defending_player, available_stratagems, target_unit_ids, snapshot
	)

	if decision.is_empty():
		decision = {
			"type": "DECLINE_REACTIVE_STRATAGEM",
			"player": defending_player,
			"_ai_description": "AI declines reactive stratagems"
		}

	decision["player"] = defending_player
	_submit_reactive_action(defending_player, decision)

# --- Reactive Stratagem: Fire Overwatch (MovementPhase) ---

func _on_movement_fire_overwatch_opportunity(defending_player: int, eligible_units: Array, enemy_unit_id: String) -> void:
	"""
	Called when the MovementPhase offers Fire Overwatch to the defending player
	after an enemy unit moves. If the defender is AI, evaluate and submit.
	"""
	if not is_ai_player(defending_player):
		return

	print("AIPlayer: Fire Overwatch opportunity for AI player %d (%d eligible units) against %s" % [
		defending_player, eligible_units.size(), enemy_unit_id])

	var snapshot = GameState.create_snapshot()
	var decision = AIDecisionMaker.evaluate_fire_overwatch(
		defending_player, eligible_units, enemy_unit_id, snapshot
	)

	decision["player"] = defending_player
	_submit_reactive_action(defending_player, decision)

# --- Reactive Stratagem: Fire Overwatch (ChargePhase — via overwatch_opportunity) ---

func _on_charge_overwatch_opportunity(moved_unit_id: String, defending_player: int, eligible_units: Array) -> void:
	"""
	Called when the ChargePhase offers Fire Overwatch to the defending player
	after a charge declaration. If the defender is AI, evaluate and submit.
	Note: ChargePhase also includes these in get_available_actions(), so the AI's
	_decide_charge handles them. This signal handler provides backup and context.
	"""
	if not is_ai_player(defending_player):
		return

	# ChargePhase includes USE/DECLINE_FIRE_OVERWATCH in get_available_actions()
	# which the AI's _decide_charge will handle via the normal evaluation loop.
	# Just trigger a re-evaluation to ensure the AI acts promptly.
	print("AIPlayer: Charge phase overwatch opportunity for AI player %d against %s" % [defending_player, moved_unit_id])
	_request_evaluation()

# --- Proactive Stratagem: Tank Shock (ChargePhase — via tank_shock_opportunity) ---

func _on_tank_shock_opportunity(charging_player: int, vehicle_unit_id: String, eligible_targets: Array) -> void:
	"""
	Called when the ChargePhase offers Tank Shock to the charging player
	after a successful charge with a VEHICLE unit. If the player is AI, evaluate and submit.
	Tank Shock is handled via get_available_actions() in _decide_charge(), so this
	signal handler just triggers a re-evaluation to ensure the AI acts promptly.
	"""
	if not is_ai_player(charging_player):
		return

	print("AIPlayer: Tank Shock opportunity for AI player %d — vehicle %s, %d eligible targets" % [
		charging_player, vehicle_unit_id, eligible_targets.size()])
	_request_evaluation()

# --- Reactive Stratagem: Heroic Intervention (ChargePhase — via heroic_intervention_opportunity) ---

func _on_heroic_intervention_opportunity(defending_player: int, eligible_units: Array, charging_unit_id: String) -> void:
	"""
	Called when the ChargePhase offers Heroic Intervention to the defending player
	after an enemy unit ends a Charge move. If the defender is AI, evaluate and submit.
	Heroic Intervention is handled via get_available_actions() in _decide_charge(), so this
	signal handler just triggers a re-evaluation to ensure the AI acts promptly.
	"""
	if not is_ai_player(defending_player):
		return

	print("AIPlayer: Heroic Intervention opportunity for AI player %d — %d eligible units against %s" % [
		defending_player, eligible_units.size(), charging_unit_id])
	_request_evaluation()

# --- T7-32: Reactive Stratagem: Counter-Offensive (FightPhase — after enemy unit fights) ---

func _on_counter_offensive_opportunity(player: int, eligible_units: Array) -> void:
	"""
	Called when the FightPhase offers Counter-Offensive to the opponent player
	after an enemy unit has fought and consolidated. If the player is AI, evaluate and submit.
	Counter-Offensive costs 2 CP and lets the AI select a unit to fight next.
	"""
	if not is_ai_player(player):
		return

	print("AIPlayer: Counter-Offensive opportunity for AI player %d — %d eligible units" % [
		player, eligible_units.size()])

	var snapshot = GameState.create_snapshot()
	var decision = AIDecisionMaker.evaluate_counter_offensive(player, eligible_units, snapshot)

	print("AIPlayer: Counter-Offensive decision for player %d — %s" % [player, decision.get("_ai_description", "?")])
	_submit_reactive_action(player, decision)

# --- Reactive Stratagem: Command Re-roll (any phase) ---

func _on_command_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary) -> void:
	"""
	Called when a phase offers Command Re-roll to a player after a dice roll.
	If the player is AI, evaluate based on the roll context and submit.
	"""
	if not is_ai_player(player):
		return

	print("AIPlayer: Command Re-roll opportunity for AI player %d — %s (roll type: %s)" % [
		player, unit_id, roll_context.get("roll_type", "unknown")])

	var snapshot = GameState.create_snapshot()
	var should_reroll = false

	var roll_type = roll_context.get("roll_type", "")
	match roll_type:
		"charge_roll":
			var total = roll_context.get("total", 0)
			var min_distance = roll_context.get("min_distance", 99.0)
			var needed = max(0.0, min_distance - 1.0)  # Subtract engagement range (1")
			should_reroll = AIDecisionMaker.evaluate_command_reroll_charge(
				player, total, int(ceil(needed)), snapshot
			)
			print("AIPlayer: Charge reroll evaluation — rolled %d, need %d, reroll: %s" % [total, int(ceil(needed)), str(should_reroll)])

		"advance_roll":
			var total = roll_context.get("total", 0)
			should_reroll = AIDecisionMaker.evaluate_command_reroll_advance(player, total, snapshot)
			print("AIPlayer: Advance reroll evaluation — rolled %d, reroll: %s" % [total, str(should_reroll)])

		"battle_shock_test":
			var total = roll_context.get("total", 0)
			var leadership = roll_context.get("leadership", 6)
			should_reroll = AIDecisionMaker.evaluate_command_reroll_battleshock(player, total, leadership, snapshot)
			print("AIPlayer: Battle-shock reroll evaluation — rolled %d, leadership %d, reroll: %s" % [total, leadership, str(should_reroll)])

		_:
			# Unknown roll type — decline
			print("AIPlayer: Unknown reroll type '%s' — declining" % roll_type)

	var decision: Dictionary
	if should_reroll:
		decision = {
			"type": "USE_COMMAND_REROLL",
			"actor_unit_id": unit_id,
			"player": player,
			"_ai_description": "AI uses Command Re-roll on %s" % roll_type
		}
	else:
		decision = {
			"type": "DECLINE_COMMAND_REROLL",
			"actor_unit_id": unit_id,
			"player": player,
			"_ai_description": "AI declines Command Re-roll on %s" % roll_type
		}

	_submit_reactive_action(player, decision)

# --- Submit reactive action ---

func _submit_reactive_action(player: int, decision: Dictionary) -> void:
	"""
	Submit an AI reactive stratagem action. Uses call_deferred to avoid
	acting during signal emission (which could cause re-entrancy issues).
	"""
	call_deferred("_execute_reactive_action_deferred", player, decision)

func _execute_reactive_action_deferred(player: int, decision: Dictionary) -> void:
	"""Execute a reactive stratagem action after the current call stack completes."""
	if not enabled or PhaseManager.game_ended:
		return

	var description = decision.get("_ai_description", str(decision.get("type", "unknown")))
	_action_log.append({
		"phase": GameState.get_current_phase(),
		"action_type": decision.get("type", ""),
		"description": description,
		"player": player
	})
	emit_signal("ai_action_taken", player, decision, description)

	print("AIPlayer: Reactive stratagem — Player %d executing: %s (%s)" % [player, decision.get("type", "?"), description])

	_current_phase_actions += 1
	var result = NetworkIntegration.route_action(decision)

	if result == null:
		push_error("AIPlayer: Reactive action route_action returned null: %s" % decision.get("type", "?"))
		return

	if not result.get("success", false):
		var error_msg = result.get("error", result.get("errors", "Unknown error"))
		push_error("AIPlayer: Reactive action failed: %s - Error: %s" % [decision.get("type", "?"), error_msg])
	else:
		print("AIPlayer: Reactive stratagem action succeeded: %s" % decision.get("type", "?"))

	# After reactive action, trigger re-evaluation for next action
	_request_evaluation()

# --- Core AI loop ---

func _evaluate_and_act() -> void:
	if not enabled or PhaseManager.game_ended:
		_end_ai_thinking()
		return

	DebugLogger.info("AIPlayer._evaluate_and_act called", {"processing_turn": _processing_turn, "enabled": enabled})
	if _processing_turn:
		DebugLogger.info("AIPlayer._evaluate_and_act - skipped (already processing)", {})
		return  # Already processing, avoid re-entrancy

	var active_player = GameState.get_active_player()
	if not is_ai_player(active_player):
		DebugLogger.info("AIPlayer._evaluate_and_act - not AI turn", {"active_player": active_player})
		_end_ai_thinking()
		return  # Not AI's turn

	# Use cached reference - get_node_or_null("/root/PhaseManager") fails in web exports
	if not _phase_manager_ref:
		_phase_manager_ref = get_node_or_null("/root/PhaseManager")
	var phase_manager = _phase_manager_ref
	if not phase_manager:
		DebugLogger.info("AIPlayer._evaluate_and_act - no PhaseManager", {})
		_end_ai_thinking()
		return
	if not phase_manager.current_phase_instance:
		DebugLogger.info("AIPlayer._evaluate_and_act - no phase instance", {})
		_end_ai_thinking()
		return  # No active phase

	# Check game completion
	if GameState.is_game_complete():
		if enabled:
			print("AIPlayer: Game is complete, disabling AI")
			enabled = false
		_end_ai_thinking()
		return

	# Safety check - prevent infinite action loops
	if _current_phase_actions >= MAX_ACTIONS_PER_PHASE:
		push_error("AIPlayer: Hit max actions (%d) for current phase! Stopping to prevent infinite loop." % MAX_ACTIONS_PER_PHASE)
		_end_ai_thinking()
		return

	DebugLogger.info("AIPlayer._evaluate_and_act - executing for player", {"player": active_player, "phase": GameState.get_current_phase()})
	_processing_turn = true
	_execute_next_action(active_player)
	_processing_turn = false
	DebugLogger.info("AIPlayer._evaluate_and_act - complete", {})

func _execute_next_action(player: int) -> void:
	var phase = GameState.get_current_phase()
	var snapshot = GameState.create_snapshot()

	# Get available actions from phase
	var phase_manager = get_node("/root/PhaseManager")
	var available = phase_manager.get_available_actions()

	if available.is_empty():
		print("AIPlayer: No available actions for player %d in phase %d" % [player, phase])
		_end_ai_thinking()
		return

	print("AIPlayer: Player %d deciding in phase %d with %d available actions" % [player, phase, available.size()])

	# Ask decision maker what to do
	var decision = AIDecisionMaker.decide(phase, snapshot, available, player)

	if decision.is_empty():
		push_warning("AIPlayer: No decision made for player %d in phase %d" % [player, phase])
		_end_ai_thinking()
		return

	# Ensure player field is set
	decision["player"] = player

	# Log for summary
	var description = decision.get("_ai_description", str(decision.get("type", "unknown")))
	_action_log.append({
		"phase": phase,
		"action_type": decision.get("type", ""),
		"description": description,
		"player": player
	})
	emit_signal("ai_action_taken", player, decision, description)

	print("AIPlayer: Player %d executing: %s (%s)" % [player, decision.get("type", "?"), description])

	# Increment safety counter
	_current_phase_actions += 1

	# Submit through standard pipeline
	var result = NetworkIntegration.route_action(decision)

	if result == null:
		push_error("AIPlayer: route_action returned null for action: %s" % decision.get("type", "?"))
		return

	if not result.get("success", false):
		var error_msg = result.get("error", result.get("errors", "Unknown error"))
		push_error("AIPlayer: Action failed: %s - Error: %s" % [decision.get("type", "?"), error_msg])
		print("AIPlayer: Failed action details: %s" % str(decision))

		# Handle failed deployment specifically
		if decision.get("type") == "DEPLOY_UNIT":
			var deploy_unit_name = _get_unit_name(decision.get("unit_id", ""))
			_log_ai_event(player, "%s deployment failed (%s) — retrying" % [deploy_unit_name, _format_error_concise(error_msg)])
			_handle_failed_deployment(player, decision)

		# Handle failed shooting — skip the unit so we don't retry the same one
		elif decision.get("type") == "SHOOT":
			var failed_unit_id = decision.get("actor_unit_id", "")
			if failed_unit_id != "":
				var shoot_unit_name = _get_unit_name(failed_unit_id)
				print("AIPlayer: Shooting failed for %s, sending SKIP_UNIT" % failed_unit_id)
				# Format the error concisely for the game log
				var shoot_errors = result.get("errors", [])
				var shoot_reason = ""
				if shoot_errors is Array and shoot_errors.size() > 0:
					# Deduplicate repeated error messages
					var unique_errors = []
					for e in shoot_errors:
						if e not in unique_errors:
							unique_errors.append(e)
					shoot_reason = "; ".join(unique_errors)
				else:
					shoot_reason = str(error_msg)
				_current_phase_actions += 1
				NetworkIntegration.route_action({
					"type": "SKIP_UNIT",
					"actor_unit_id": failed_unit_id,
					"player": player,
					"_ai_description": "Skipped %s — %s" % [shoot_unit_name, shoot_reason]
				})
	else:
		# Emit signal for successful deployments so Main.gd can create visuals
		if decision.get("type") == "DEPLOY_UNIT":
			var deployed_unit_id = decision.get("unit_id", "")
			if deployed_unit_id != "":
				print("AIPlayer: Emitting ai_unit_deployed for %s (player %d)" % [deployed_unit_id, player])
				emit_signal("ai_unit_deployed", player, deployed_unit_id)

		# T7-16: Emit signal for reinforcement arrivals so Main.gd creates visuals
		elif decision.get("type") == "PLACE_REINFORCEMENT":
			var reinforced_unit_id = decision.get("unit_id", "")
			if reinforced_unit_id != "":
				print("AIPlayer: Emitting ai_unit_deployed for reinforcement %s (player %d)" % [reinforced_unit_id, player])
				emit_signal("ai_unit_deployed", player, reinforced_unit_id)

		# Handle multi-step movement: BEGIN_NORMAL_MOVE, BEGIN_ADVANCE, or BEGIN_FALL_BACK with pre-computed destinations
		elif decision.get("type") in ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK"] and decision.has("_ai_model_destinations"):
			_execute_ai_movement(player, decision)

		# Handle multi-step scout movement: BEGIN_SCOUT_MOVE with pre-computed destinations
		elif decision.get("type") == "BEGIN_SCOUT_MOVE" and decision.has("_ai_scout_destinations"):
			_execute_ai_scout_movement(player, decision)

# --- AI Movement execution ---

func _execute_ai_movement(player: int, decision: Dictionary) -> void:
	var unit_id = decision.get("actor_unit_id", "")
	var destinations = decision.get("_ai_model_destinations", {})
	var description = decision.get("_ai_description", "AI movement")
	var unit_name = _get_unit_name(unit_id)

	if unit_id == "" or destinations.is_empty():
		print("AIPlayer: AI movement called with no unit or destinations")
		return

	print("AIPlayer: Executing AI movement for %s — staging %d models" % [unit_id, destinations.size()])

	var staged_count = 0
	var failed_count = 0
	var failure_reasons = []

	# Stage each model's destination
	for model_id in destinations:
		var dest = destinations[model_id]
		var stage_action = {
			"type": "STAGE_MODEL_MOVE",
			"actor_unit_id": unit_id,
			"player": player,
			"payload": {
				"model_id": model_id,
				"dest": dest,  # [x, y] array
				"rotation": 0.0
			}
		}

		_current_phase_actions += 1
		var stage_result = NetworkIntegration.route_action(stage_action)

		if stage_result != null and stage_result.get("success", false):
			staged_count += 1
			print("AIPlayer: Staged model %s to (%.0f, %.0f)" % [model_id, dest[0], dest[1]])
		else:
			failed_count += 1
			var errors = stage_result.get("errors", []) if stage_result != null else []
			var error_msg = errors[0] if errors is Array and errors.size() > 0 else str(stage_result.get("error", "unknown")) if stage_result != null else "null result"
			failure_reasons.append(error_msg)
			print("AIPlayer: Failed to stage model %s: %s" % [model_id, error_msg])

	# Confirm the unit move (even if some models failed — partial moves are valid)
	if staged_count > 0:
		var confirm_action = {
			"type": "CONFIRM_UNIT_MOVE",
			"actor_unit_id": unit_id,
			"player": player
		}

		_current_phase_actions += 1
		var confirm_result = NetworkIntegration.route_action(confirm_action)

		if confirm_result != null and confirm_result.get("success", false):
			print("AIPlayer: Confirmed movement for %s (%d/%d models staged)" % [
				unit_id, staged_count, staged_count + failed_count])
			_action_log.append({
				"phase": GameState.get_current_phase(),
				"action_type": "CONFIRM_UNIT_MOVE",
				"description": "%s (moved %d models)" % [description, staged_count],
				"player": player
			})
		else:
			var error_msg = "" if confirm_result == null else confirm_result.get("error", confirm_result.get("errors", ""))
			push_error("AIPlayer: Failed to confirm movement for %s: %s" % [unit_id, error_msg])
			# Try to reset the move to recover
			_current_phase_actions += 1
			NetworkIntegration.route_action({
				"type": "RESET_UNIT_MOVE",
				"actor_unit_id": unit_id,
				"player": player
			})
			# Fall back to remain stationary — _ai_description will be logged by GameEventLog
			_current_phase_actions += 1
			NetworkIntegration.route_action({
				"type": "REMAIN_STATIONARY",
				"actor_unit_id": unit_id,
				"player": player,
				"_ai_description": "%s remains stationary (confirm failed: %s)" % [unit_name, error_msg]
			})
	else:
		# No models could be staged — reset and remain stationary
		var reason = failure_reasons[0] if failure_reasons.size() > 0 else "unknown"
		print("AIPlayer: No models staged for %s, resetting move" % unit_id)
		_current_phase_actions += 1
		NetworkIntegration.route_action({
			"type": "RESET_UNIT_MOVE",
			"actor_unit_id": unit_id,
			"player": player
		})
		# Fall back to remain stationary — _ai_description will be logged by GameEventLog
		_current_phase_actions += 1
		NetworkIntegration.route_action({
			"type": "REMAIN_STATIONARY",
			"actor_unit_id": unit_id,
			"player": player,
			"_ai_description": "%s remains stationary (move failed: %s)" % [unit_name, reason]
		})

# --- AI Scout Movement execution ---

func _execute_ai_scout_movement(player: int, decision: Dictionary) -> void:
	var unit_id = decision.get("unit_id", "")
	var destinations = decision.get("_ai_scout_destinations", {})
	var description = decision.get("_ai_description", "AI scout movement")
	var unit_name = _get_unit_name(unit_id)

	if unit_id == "" or destinations.is_empty():
		print("AIPlayer: AI scout movement called with no unit or destinations")
		return

	print("AIPlayer: Executing AI scout movement for %s — staging %d models" % [unit_id, destinations.size()])

	# Stage each model's destination using SET_SCOUT_MODEL_DEST
	var staged_count = 0
	var failed_count = 0
	var failure_reasons = []

	for model_id in destinations:
		var dest = destinations[model_id]
		var stage_action = {
			"type": "SET_SCOUT_MODEL_DEST",
			"unit_id": unit_id,
			"model_id": model_id,
			"player": player,
			"destination": {"x": dest[0], "y": dest[1]}
		}

		_current_phase_actions += 1
		var stage_result = NetworkIntegration.route_action(stage_action)

		if stage_result != null and stage_result.get("success", false):
			staged_count += 1
			print("AIPlayer: Staged scout model %s to (%.0f, %.0f)" % [model_id, dest[0], dest[1]])
		else:
			failed_count += 1
			var errors = stage_result.get("errors", []) if stage_result != null else []
			var error_msg = errors[0] if errors is Array and errors.size() > 0 else str(stage_result.get("error", "unknown")) if stage_result != null else "null result"
			failure_reasons.append(error_msg)
			print("AIPlayer: Failed to stage scout model %s: %s" % [model_id, error_msg])

	# Confirm the scout move (even if some models failed — partial moves are valid)
	if staged_count > 0:
		var confirm_action = {
			"type": "CONFIRM_SCOUT_MOVE",
			"unit_id": unit_id,
			"player": player
		}

		_current_phase_actions += 1
		var confirm_result = NetworkIntegration.route_action(confirm_action)

		if confirm_result != null and confirm_result.get("success", false):
			print("AIPlayer: Confirmed scout movement for %s (%d/%d models staged)" % [
				unit_id, staged_count, staged_count + failed_count])
			_action_log.append({
				"phase": GameState.get_current_phase(),
				"action_type": "CONFIRM_SCOUT_MOVE",
				"description": "%s (moved %d models)" % [description, staged_count],
				"player": player
			})
		else:
			var error_msg = "" if confirm_result == null else confirm_result.get("error", confirm_result.get("errors", ""))
			push_error("AIPlayer: Failed to confirm scout movement for %s: %s" % [unit_id, error_msg])
			# Fall back to skipping the scout move
			_current_phase_actions += 1
			NetworkIntegration.route_action({
				"type": "SKIP_SCOUT_MOVE",
				"unit_id": unit_id,
				"player": player,
				"_ai_description": "%s scout move skipped (confirm failed: %s)" % [unit_name, error_msg]
			})
	else:
		# No models could be staged — skip the scout move
		var reason = failure_reasons[0] if failure_reasons.size() > 0 else "unknown"
		print("AIPlayer: No scout models staged for %s, skipping" % unit_id)
		_current_phase_actions += 1
		NetworkIntegration.route_action({
			"type": "SKIP_SCOUT_MOVE",
			"unit_id": unit_id,
			"player": player,
			"_ai_description": "%s scout move skipped (staging failed: %s)" % [unit_name, reason]
		})

# --- Helpers ---

func _get_unit_name(unit_id: String) -> String:
	if unit_id == "":
		return "Unknown"
	var unit = GameState.state.get("units", {}).get(unit_id, {})
	return unit.get("meta", {}).get("name", unit_id)

func _log_ai_event(player: int, text: String) -> void:
	"""Log an AI event to the GameEventLog panel."""
	var game_event_log = get_node_or_null("/root/GameEventLog")
	if game_event_log and game_event_log.has_method("add_ai_entry"):
		game_event_log.add_ai_entry(player, text)

func _format_error_concise(error) -> String:
	"""Format error messages concisely, deduplicating arrays."""
	if error is Array:
		var unique = []
		for e in error:
			var s = str(e)
			if s not in unique:
				unique.append(s)
		return "; ".join(unique)
	return str(error)

# --- Deployment retry logic ---

func _handle_failed_deployment(player: int, original_decision: Dictionary) -> void:
	var unit_id = original_decision.get("unit_id", "")
	if unit_id == "":
		return

	var snapshot = GameState.create_snapshot()
	var unit = snapshot.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	print("AIPlayer: Deployment retry for %s (player %d)" % [unit_name, player])

	var zone_bounds = AIDecisionMaker._get_deployment_zone_bounds(snapshot, player)
	var models = unit.get("models", [])
	var first_model = models[0] if models.size() > 0 else {}
	var base_mm = first_model.get("base_mm", 32)
	var base_type = first_model.get("base_type", "circular")
	var base_dimensions = first_model.get("base_dimensions", {})
	var deployed_models = AIDecisionMaker._get_all_deployed_model_positions(snapshot)

	var zone_width = zone_bounds.max_x - zone_bounds.min_x
	var zone_height = zone_bounds.max_y - zone_bounds.min_y

	# Try up to 3 retries with positions spread across different zone quadrants
	for attempt in range(3):
		# Pick a different quadrant each retry
		var quadrant_x = (attempt % 2) * 0.5
		var quadrant_y = (attempt / 2) * 0.5
		# Add jitter so we don't land on exact same spots
		var jitter_x = (randf() - 0.5) * zone_width * 0.2
		var jitter_y = (randf() - 0.5) * zone_height * 0.2

		var retry_center = Vector2(
			zone_bounds.min_x + zone_width * (0.25 + quadrant_x) + jitter_x,
			zone_bounds.min_y + zone_height * (0.25 + quadrant_y) + jitter_y
		)
		retry_center.x = clamp(retry_center.x, zone_bounds.min_x + 80, zone_bounds.max_x - 80)
		retry_center.y = clamp(retry_center.y, zone_bounds.min_y + 80, zone_bounds.max_y - 80)

		var positions = AIDecisionMaker._generate_formation_positions(retry_center, models.size(), base_mm, zone_bounds)
		positions = AIDecisionMaker._resolve_formation_collisions(positions, base_mm, deployed_models, zone_bounds, base_type, base_dimensions)

		var rotations = []
		for i in range(models.size()):
			rotations.append(0.0)

		var retry_action = {
			"type": "DEPLOY_UNIT",
			"unit_id": unit_id,
			"model_positions": positions,
			"model_rotations": rotations,
			"player": player,
			"_ai_description": "Deployed %s (retry %d)" % [unit_name, attempt + 1]
		}

		print("AIPlayer: Deployment retry %d for %s at center (%.0f, %.0f)" % [attempt + 1, unit_name, retry_center.x, retry_center.y])

		_current_phase_actions += 1
		var result = NetworkIntegration.route_action(retry_action)
		if result != null and result.get("success", false):
			print("AIPlayer: Deployment retry %d succeeded for %s" % [attempt + 1, unit_name])
			_action_log.append({
				"phase": GameState.get_current_phase(),
				"action_type": "DEPLOY_UNIT",
				"description": "Deployed %s (retry %d)" % [unit_name, attempt + 1],
				"player": player
			})
			print("AIPlayer: Emitting ai_unit_deployed for %s (player %d) after retry" % [unit_id, player])
			emit_signal("ai_unit_deployed", player, unit_id)
			return

		var error_msg = "" if result == null else result.get("error", result.get("errors", ""))
		print("AIPlayer: Deployment retry %d failed for %s: %s" % [attempt + 1, unit_name, error_msg])

	# All retries failed — fallback to reserves
	_fallback_to_reserves(player, unit_id, unit_name)

func _fallback_to_reserves(player: int, unit_id: String, unit_name: String) -> void:
	print("AIPlayer: All deployment retries failed for %s, placing in reserves" % unit_name)
	_log_ai_event(player, "%s deployment failed after retries — placed in Strategic Reserves" % unit_name)

	var reserves_action = {
		"type": "PLACE_IN_RESERVES",
		"unit_id": unit_id,
		"reserve_type": "strategic_reserves",
		"player": player,
		"_ai_description": "%s placed in reserves (fallback)" % unit_name
	}

	_current_phase_actions += 1
	var result = NetworkIntegration.route_action(reserves_action)

	if result != null and result.get("success", false):
		print("AIPlayer: Successfully placed %s in strategic reserves" % unit_name)
		_action_log.append({
			"phase": GameState.get_current_phase(),
			"action_type": "PLACE_IN_RESERVES",
			"description": "%s placed in reserves (fallback)" % unit_name,
			"player": player
		})
	else:
		var error_msg = "" if result == null else result.get("error", result.get("errors", ""))
		push_error("AIPlayer: Failed to place %s in reserves: %s" % [unit_name, error_msg])
