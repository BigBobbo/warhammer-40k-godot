extends Node
const GameStateData = preload("res://autoloads/GameState.gd")
const AIDifficultyConfigData = preload("res://scripts/AIDifficultyConfig.gd")
const AIMovementPathVisualScript = preload("res://scripts/AIMovementPathVisual.gd")

# AIPlayer - Autoload controller for AI opponents
# Monitors game signals and submits actions through NetworkIntegration.route_action()
# when the active player is configured as AI.
#
# Handles both active-turn decisions (via _evaluate_and_act) and reactive stratagem
# decisions (via phase signal connections) for stratagems like Fire Overwatch,
# Go to Ground, Smokescreen, and Command Re-roll.

# Configuration
var ai_players: Dictionary = {}  # player_id (int) -> true/false (is AI)
var ai_difficulty: Dictionary = {}  # player_id (int) -> AIDifficultyConfigData.Difficulty value
var enabled: bool = false
var _processing_turn: bool = false  # Guard against re-entrant calls
var _action_log: Array = []  # Log of AI actions for summary display
var _turn_history: Array = []  # T7-56: Per-turn action history [{round, player, phase_range, actions}]
var _turn_start_log_index: int = 0  # T7-56: Index into _action_log where current thinking sequence started
var _current_phase_actions: int = 0  # Safety counter per phase
const MAX_ACTIONS_PER_PHASE: int = 200  # Safety limit to prevent infinite loops

# T7-36: AI speed presets — configurable delay between AI actions
enum AISpeedPreset { FAST, NORMAL, SLOW, STEP_BY_STEP }
const AI_SPEED_DELAYS: Dictionary = {
	AISpeedPreset.FAST: 0.0,
	AISpeedPreset.NORMAL: 0.2,
	AISpeedPreset.SLOW: 0.5,
	AISpeedPreset.STEP_BY_STEP: 0.0,  # Step-by-step uses manual continue, not timed delays
}
const AI_SPEED_NAMES: Dictionary = {
	AISpeedPreset.FAST: "Fast",
	AISpeedPreset.NORMAL: "Normal",
	AISpeedPreset.SLOW: "Slow",
	AISpeedPreset.STEP_BY_STEP: "Step-by-step",
}
var _ai_speed_preset: int = AISpeedPreset.NORMAL
var _step_by_step_paused: bool = false  # T7-36: True when waiting for user to continue in step-by-step mode

# Frame-paced evaluation: ensures the renderer gets to draw between AI actions
var _needs_evaluation: bool = false
var _eval_timer: float = 0.0
const AI_ACTION_DELAY: float = 0.05  # 50ms fallback (overridden by _ai_speed_preset)

# T7-55: Spectator mode (AI vs AI) — slower action delay so humans can follow
const SPECTATOR_ACTION_DELAY: float = 0.5  # 500ms between actions in spectator mode
const SPECTATOR_SPEED_PRESETS: Array = [0.25, 0.5, 1.0, 2.0, 4.0]  # Speed multipliers
var _spectator_speed_index: int = 2  # Default 1.0x (index into SPECTATOR_SPEED_PRESETS)
var _spectator_mode: bool = false  # Cached: true when both players are AI
var _phase_action_counts: Dictionary = {}  # player -> {action_type -> count} for turn summaries

# T7-57: Per-game performance tracking for post-game summary
var _game_performance: Dictionary = {}  # player -> {cp_spent, units_lost, units_killed, objectives_per_round, key_moments}

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

# T7-36: AI speed control signals
signal ai_speed_changed(preset: int, name: String)
signal step_by_step_waiting()  # Emitted when step-by-step mode pauses for user input

# T7-55: Spectator mode signals
signal spectator_speed_changed(speed: float)
signal spectator_phase_summary(player: int, phase: int, summary: Dictionary)

# T7-56: Turn history signal — emitted when a turn's actions are stored
signal turn_history_updated()

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

	# T7-57: Connect to MissionManager signals for performance tracking
	if has_node("/root/MissionManager"):
		var mission_mgr = get_node("/root/MissionManager")
		mission_mgr.victory_points_scored.connect(_on_vp_scored)
		print("AIPlayer: Connected to MissionManager.victory_points_scored")

	set_process(true)
	print("AIPlayer: Ready (disabled until configured)")

func _process(delta: float) -> void:
	if not _needs_evaluation or not enabled or PhaseManager.game_ended or _processing_turn:
		return
	# T7-36: In step-by-step mode, wait for user to continue
	if _step_by_step_paused:
		return
	_eval_timer -= delta
	if _eval_timer <= 0.0:
		_needs_evaluation = false
		_evaluate_and_act()

func _request_evaluation() -> void:
	"""Schedule an AI evaluation for the next frame(s), giving the renderer time to draw."""
	_needs_evaluation = true
	# T7-36: Use configured speed preset delay (or spectator delay in AI-vs-AI mode)
	_eval_timer = _get_effective_action_delay()

	# T7-36: In step-by-step mode, pause after the AI has already taken at least one action
	if _ai_speed_preset == AISpeedPreset.STEP_BY_STEP and _ai_thinking:
		_step_by_step_paused = true
		emit_signal("step_by_step_waiting")
		print("AIPlayer: T7-36 Step-by-step mode — paused, waiting for user continue")

	# T7-20: Signal that AI is now thinking (only on first evaluation of a sequence)
	if not _ai_thinking:
		var active_player = GameState.get_active_player()
		if is_ai_player(active_player):
			_ai_thinking = true
			_turn_start_log_index = _action_log.size()  # T7-56: Track where this turn's actions start
			emit_signal("ai_turn_started", active_player)
			print("AIPlayer: AI thinking started for player %d" % active_player)

func _end_ai_thinking() -> void:
	"""T7-20: Signal that the AI has finished its current thinking sequence."""
	if _ai_thinking:
		_ai_thinking = false
		_step_by_step_paused = false  # T7-36: Clear step-by-step pause when thinking ends
		var active_player = GameState.get_active_player()
		var actions_snapshot = _action_log.duplicate()
		emit_signal("ai_turn_ended", active_player, actions_snapshot)
		# T7-56: Store only this turn's actions (slice from start index to end)
		var turn_actions = _action_log.slice(_turn_start_log_index)
		_store_turn_history(active_player, turn_actions)
		print("AIPlayer: AI thinking ended for player %d" % active_player)

func configure(player_types: Dictionary, difficulty_levels: Dictionary = {}) -> void:
	"""
	Called from Main.gd during initialization.
	player_types: {1: "HUMAN" or "AI", 2: "HUMAN" or "AI"}
	difficulty_levels: {1: AIDifficultyConfigData.Difficulty value, 2: ...} (optional)
	"""
	ai_players.clear()
	ai_difficulty.clear()
	_action_log.clear()
	_turn_history.clear()  # T7-56: Reset turn history on reconfigure
	_current_phase_actions = 0

	for player_id in player_types:
		var pid = int(player_id)
		ai_players[pid] = (player_types[player_id] == "AI")
		# T7-40: Set difficulty per-player (default Normal for backwards compatibility)
		ai_difficulty[pid] = difficulty_levels.get(pid, difficulty_levels.get(player_id, AIDifficultyConfigData.Difficulty.NORMAL))
	enabled = ai_players.values().has(true)

	# T7-55: Detect spectator mode (both players are AI)
	_spectator_mode = ai_players.get(1, false) and ai_players.get(2, false)
	_phase_action_counts.clear()

	# T7-57: Initialize per-game performance tracking
	_game_performance.clear()
	for pid in ai_players:
		if ai_players[pid]:
			_game_performance[pid] = {
				"cp_spent": 0,
				"units_lost": 0,
				"units_killed": 0,
				"objectives_per_round": {},  # round -> count
				"key_moments": [],  # [{round, text}]
			}

	var p1_diff = AIDifficultyConfigData.difficulty_name(ai_difficulty.get(1, AIDifficultyConfigData.Difficulty.NORMAL))
	var p2_diff = AIDifficultyConfigData.difficulty_name(ai_difficulty.get(2, AIDifficultyConfigData.Difficulty.NORMAL))
	print("AIPlayer: Configured - P1=%s (%s), P2=%s (%s), enabled=%s, spectator=%s" % [
		player_types.get(1, player_types.get("1", "HUMAN")), p1_diff,
		player_types.get(2, player_types.get("2", "HUMAN")), p2_diff,
		enabled, _spectator_mode])

	# If AI should act right away (e.g., Player 1 is AI in deployment), kick off
	if enabled:
		_request_evaluation()

func is_ai_player(player: int) -> bool:
	return enabled and ai_players.get(player, false)

func get_difficulty(player: int) -> int:
	"""T7-40: Get the difficulty level for a given player."""
	return ai_difficulty.get(player, AIDifficultyConfigData.Difficulty.NORMAL)

func get_action_log() -> Array:
	return _action_log.duplicate()

func clear_action_log() -> void:
	_action_log.clear()

# T7-56: Per-turn action history for AI turn replay panel

func _store_turn_history(player: int, actions: Array) -> void:
	"""Store a snapshot of the AI's actions for this thinking sequence."""
	if actions.is_empty():
		return
	var entry = {
		"battle_round": GameState.get_battle_round(),
		"player": player,
		"phase": GameState.get_current_phase(),
		"timestamp": Time.get_unix_time_from_system(),
		"actions": actions.duplicate(true),
	}
	_turn_history.append(entry)
	emit_signal("turn_history_updated")
	print("AIPlayer: T7-56 Stored turn history entry #%d (round %d, player %d, %d actions)" % [
		_turn_history.size(), entry.battle_round, player, actions.size()])

func get_turn_history() -> Array:
	"""T7-56: Return the full turn history array (read-only duplicate)."""
	return _turn_history.duplicate(true)

func get_turn_history_count() -> int:
	"""T7-56: Return the number of stored turn history entries."""
	return _turn_history.size()

# --- Signal handlers ---

func _on_phase_changed(_new_phase) -> void:
	if not enabled or PhaseManager.game_ended:
		return

	# T7-55: Emit phase summary before resetting counters (spectator mode)
	if _spectator_mode:
		_emit_phase_summary_for_current_phase()

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

	# P2-25: Distraction Grot signal
	if phase.has_signal("distraction_grot_available"):
		var callable_dg = Callable(self, "_on_distraction_grot_available")
		phase.distraction_grot_available.connect(callable_dg)
		_connected_phase_signals.append({"signal_name": "distraction_grot_available", "callable": callable_dg})
		print("AIPlayer: Connected to ShootingPhase.distraction_grot_available")

	# --- MovementPhase signals ---
	if phase.has_signal("fire_overwatch_opportunity"):
		var callable = Callable(self, "_on_movement_fire_overwatch_opportunity")
		phase.fire_overwatch_opportunity.connect(callable)
		_connected_phase_signals.append({"signal_name": "fire_overwatch_opportunity", "callable": callable})
		print("AIPlayer: Connected to MovementPhase.fire_overwatch_opportunity")

	# P2-25: Bomb Squigs signal
	if phase.has_signal("bomb_squigs_available"):
		var callable_bs = Callable(self, "_on_bomb_squigs_available")
		phase.bomb_squigs_available.connect(callable_bs)
		_connected_phase_signals.append({"signal_name": "bomb_squigs_available", "callable": callable_bs})
		print("AIPlayer: Connected to MovementPhase.bomb_squigs_available")

	if phase.has_signal("ability_reroll_opportunity"):
		var callable_ar = Callable(self, "_on_ability_reroll_opportunity")
		phase.ability_reroll_opportunity.connect(callable_ar)
		_connected_phase_signals.append({"signal_name": "ability_reroll_opportunity", "callable": callable_ar})
		print("AIPlayer: Connected to phase.ability_reroll_opportunity")

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

	# T7-35: Rapid Ingress in Movement Phase (end of opponent's movement)
	if phase.has_signal("rapid_ingress_opportunity"):
		var callable = Callable(self, "_on_movement_rapid_ingress_opportunity")
		phase.rapid_ingress_opportunity.connect(callable)
		_connected_phase_signals.append({"signal_name": "rapid_ingress_opportunity", "callable": callable})
		print("AIPlayer: Connected to MovementPhase.rapid_ingress_opportunity")

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

	var difficulty = get_difficulty(defending_player)
	print("AIPlayer: Reactive stratagem opportunity for AI player %d (stratagems: %d, targets: %d, difficulty: %s)" % [
		defending_player, available_stratagems.size(), target_unit_ids.size(), AIDifficultyConfigData.difficulty_name(difficulty)])

	# T7-40: Easy/Normal AI skips reactive stratagems
	if not AIDifficultyConfigData.use_stratagems(difficulty):
		var decline = {
			"type": "DECLINE_REACTIVE_STRATAGEM",
			"player": defending_player,
			"_ai_description": "AI declines reactive stratagems (difficulty: %s)" % AIDifficultyConfigData.difficulty_name(difficulty)
		}
		_submit_reactive_action(defending_player, decline)
		return

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

# --- P2-25: Distraction Grot (ShootingPhase) ---

func _on_distraction_grot_available(unit_id: String, player: int) -> void:
	"""
	Called when the ShootingPhase offers Distraction Grot (5+ invuln) to the defending player.
	AI always activates this free ability since it has no cost.
	"""
	if not is_ai_player(player):
		return

	print("AIPlayer: P2-25 Distraction Grot available for AI player %d, unit %s — auto-activating" % [player, unit_id])

	var decision = {
		"type": "USE_DISTRACTION_GROT",
		"actor_unit_id": unit_id,
		"player": player,
		"_ai_description": "AI activates Distraction Grot (5+ invuln, free ability)"
	}
	_submit_reactive_action(player, decision)

# --- P2-25: Bomb Squigs (MovementPhase) ---

func _on_bomb_squigs_available(unit_id: String, player: int, eligible_targets: Array) -> void:
	"""
	Called when the MovementPhase offers Bomb Squigs after a Normal move.
	AI always activates this free once-per-battle ability.
	"""
	if not is_ai_player(player):
		return

	print("AIPlayer: P2-25 Bomb Squigs available for AI player %d, unit %s — auto-activating" % [player, unit_id])

	var target_unit_id = ""
	if not eligible_targets.is_empty():
		target_unit_id = eligible_targets[0].get("target_unit_id", "")

	var decision = {
		"type": "USE_BOMB_SQUIGS",
		"actor_unit_id": unit_id,
		"target_unit_id": target_unit_id,
		"player": player,
		"_ai_description": "AI activates Bomb Squigs (D3 mortal wounds, free ability)"
	}
	_submit_reactive_action(player, decision)

# --- Reactive Stratagem: Fire Overwatch (MovementPhase) ---

func _on_movement_fire_overwatch_opportunity(defending_player: int, eligible_units: Array, enemy_unit_id: String) -> void:
	"""
	Called when the MovementPhase offers Fire Overwatch to the defending player
	after an enemy unit moves. If the defender is AI, evaluate and submit.
	"""
	if not is_ai_player(defending_player):
		return

	var difficulty = get_difficulty(defending_player)
	print("AIPlayer: Fire Overwatch opportunity for AI player %d (%d eligible units) against %s (difficulty: %s)" % [
		defending_player, eligible_units.size(), enemy_unit_id, AIDifficultyConfigData.difficulty_name(difficulty)])

	# T7-40: Easy AI never uses overwatch; Normal+ evaluates
	if not AIDifficultyConfigData.use_overwatch(difficulty):
		var decline = {
			"type": "DECLINE_FIRE_OVERWATCH",
			"player": defending_player,
			"_ai_description": "AI declines Fire Overwatch (difficulty: %s)" % AIDifficultyConfigData.difficulty_name(difficulty)
		}
		_submit_reactive_action(defending_player, decline)
		return

	var snapshot = GameState.create_snapshot()
	var decision = AIDecisionMaker.evaluate_fire_overwatch(
		defending_player, eligible_units, enemy_unit_id, snapshot
	)

	decision["player"] = defending_player
	_submit_reactive_action(defending_player, decision)

# --- Reactive Stratagem: Rapid Ingress (MovementPhase — end of opponent's movement, T7-35) ---

func _on_movement_rapid_ingress_opportunity(defending_player: int, eligible_units: Array) -> void:
	"""
	Called when the MovementPhase offers Rapid Ingress to the non-active player
	at the end of the opponent's Movement phase. If the defender is AI, evaluate
	whether to spend 1 CP to bring a reserve unit onto the board.
	"""
	if not is_ai_player(defending_player):
		return  # Not our AI — let human handle it

	var difficulty = get_difficulty(defending_player)
	print("AIPlayer: Rapid Ingress opportunity for AI player %d (%d eligible units, difficulty: %s)" % [
		defending_player, eligible_units.size(), AIDifficultyConfigData.difficulty_name(difficulty)])

	# T7-40: Only Hard+ AI uses stratagems
	if not AIDifficultyConfigData.use_stratagems(difficulty):
		var decline = {
			"type": "DECLINE_RAPID_INGRESS",
			"player": defending_player,
			"_ai_description": "AI declines Rapid Ingress (difficulty: %s)" % AIDifficultyConfigData.difficulty_name(difficulty)
		}
		_submit_reactive_action(defending_player, decline)
		return

	var snapshot = GameState.create_snapshot()
	var decision = AIDecisionMaker.evaluate_rapid_ingress(defending_player, eligible_units, snapshot)

	if decision.is_empty():
		decision = {
			"type": "DECLINE_RAPID_INGRESS",
			"player": defending_player,
			"_ai_description": "AI declines Rapid Ingress"
		}

	decision["player"] = defending_player

	# If declining, submit as normal reactive action
	if decision.get("type") == "DECLINE_RAPID_INGRESS":
		_submit_reactive_action(defending_player, decision)
		return

	# Two-step process: USE_RAPID_INGRESS, then PLACE_RAPID_INGRESS_REINFORCEMENT
	var placement = decision.get("_placement_action", {})
	decision.erase("_placement_action")  # Remove internal data before submitting

	call_deferred("_execute_rapid_ingress_sequence", defending_player, decision, placement)

func _execute_rapid_ingress_sequence(player: int, use_action: Dictionary, placement_action: Dictionary) -> void:
	"""Execute the two-step Rapid Ingress sequence: USE_RAPID_INGRESS then PLACE_RAPID_INGRESS_REINFORCEMENT."""
	if not enabled or PhaseManager.game_ended:
		return

	# Step 1: USE_RAPID_INGRESS (select the unit and spend CP)
	var use_description = use_action.get("_ai_description", "AI uses Rapid Ingress")
	_action_log.append({
		"phase": GameState.get_current_phase(),
		"action_type": use_action.get("type", ""),
		"description": use_description,
		"player": player
	})
	emit_signal("ai_action_taken", player, use_action, use_description)

	if _spectator_mode:
		_track_action_for_summary(player, use_action.get("type", ""), GameState.get_current_phase())

	# T7-37: Log the stratagem use as a key event
	_log_ai_event(player, use_description)

	# T7-57: Track CP spent (Rapid Ingress costs 1 CP)
	record_ai_cp_spent(player, 1)
	record_ai_key_moment(player, use_description)

	print("AIPlayer: Rapid Ingress Step 1 — Player %d executing: %s" % [player, use_description])

	_current_phase_actions += 1
	var result = NetworkIntegration.route_action(use_action)

	if result == null or not result.get("success", false):
		var error_msg = "" if result == null else result.get("error", result.get("errors", "Unknown error"))
		push_error("AIPlayer: Rapid Ingress USE action failed: %s" % error_msg)
		# Attempt to decline gracefully
		_current_phase_actions += 1
		NetworkIntegration.route_action({
			"type": "DECLINE_RAPID_INGRESS",
			"player": player,
			"_ai_description": "AI declines Rapid Ingress (USE failed: %s)" % error_msg
		})
		_request_evaluation()
		return

	print("AIPlayer: Rapid Ingress Step 1 succeeded — now placing unit")

	# Step 2: PLACE_RAPID_INGRESS_REINFORCEMENT (place the unit on the board)
	placement_action["player"] = player
	var place_description = placement_action.get("_ai_description", "Rapid Ingress placement")
	_action_log.append({
		"phase": GameState.get_current_phase(),
		"action_type": placement_action.get("type", ""),
		"description": place_description,
		"player": player
	})
	emit_signal("ai_action_taken", player, placement_action, place_description)

	print("AIPlayer: Rapid Ingress Step 2 — Player %d executing: %s" % [player, place_description])

	_current_phase_actions += 1
	var place_result = NetworkIntegration.route_action(placement_action)

	if place_result == null or not place_result.get("success", false):
		var error_msg = "" if place_result == null else place_result.get("error", place_result.get("errors", "Unknown error"))
		push_error("AIPlayer: Rapid Ingress PLACEMENT failed: %s" % error_msg)
	else:
		var unit_id = placement_action.get("unit_id", "")
		if unit_id != "":
			print("AIPlayer: Emitting ai_unit_deployed for Rapid Ingress %s (player %d)" % [unit_id, player])
			emit_signal("ai_unit_deployed", player, unit_id)
		print("AIPlayer: Rapid Ingress complete — unit placed successfully")

	_request_evaluation()

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

	var difficulty = get_difficulty(player)
	print("AIPlayer: Counter-Offensive opportunity for AI player %d — %d eligible units (difficulty: %s)" % [
		player, eligible_units.size(), AIDifficultyConfigData.difficulty_name(difficulty)])

	# T7-40: Only Hard+ AI uses Counter-Offensive
	if not AIDifficultyConfigData.use_counter_offensive(difficulty):
		var decline = {
			"type": "DECLINE_COUNTER_OFFENSIVE",
			"player": player,
			"_ai_description": "AI declines Counter-Offensive (difficulty: %s)" % AIDifficultyConfigData.difficulty_name(difficulty)
		}
		_submit_reactive_action(player, decline)
		return

	var snapshot = GameState.create_snapshot()
	var decision = AIDecisionMaker.evaluate_counter_offensive(player, eligible_units, snapshot)

	print("AIPlayer: Counter-Offensive decision for player %d — %s" % [player, decision.get("_ai_description", "?")])
	_submit_reactive_action(player, decision)

# --- Reactive Stratagem: Command Re-roll (any phase) ---

func _on_ability_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary) -> void:
	"""
	Called when a phase offers a free ability reroll (e.g. Swift Onslaught) to a player.
	Since it's free (no CP cost), AI should always use it if the charge roll is insufficient.
	"""
	if not is_ai_player(player):
		return

	var total = roll_context.get("total", 0)
	var min_distance = roll_context.get("min_distance", 99.0)
	var needed = max(0.0, min_distance - 1.0)  # Subtract engagement range (1")
	var ability_name = roll_context.get("ability_name", "ability")

	# Since it's free, always reroll if the roll is insufficient
	var should_reroll = total < int(ceil(needed))

	print("AIPlayer: Ability reroll (%s) for AI player %d — rolled %d, need %d, reroll: %s" % [
		ability_name, player, total, int(ceil(needed)), str(should_reroll)])

	var decision: Dictionary
	if should_reroll:
		decision = {
			"type": "USE_ABILITY_REROLL",
			"actor_unit_id": unit_id,
			"player": player,
			"_ai_description": "AI uses %s reroll on charge" % ability_name
		}
	else:
		decision = {
			"type": "DECLINE_ABILITY_REROLL",
			"actor_unit_id": unit_id,
			"player": player,
			"_ai_description": "AI declines %s reroll (charge already sufficient)" % ability_name
		}

	_submit_reactive_action(player, decision)

func _on_command_reroll_opportunity(unit_id: String, player: int, roll_context: Dictionary) -> void:
	"""
	Called when a phase offers Command Re-roll to a player after a dice roll.
	If the player is AI, evaluate based on the roll context and submit.
	"""
	if not is_ai_player(player):
		return

	var difficulty = get_difficulty(player)
	print("AIPlayer: Command Re-roll opportunity for AI player %d — %s (roll type: %s, difficulty: %s)" % [
		player, unit_id, roll_context.get("roll_type", "unknown"), AIDifficultyConfigData.difficulty_name(difficulty)])

	# T7-40: Easy AI never uses Command Re-roll
	if not AIDifficultyConfigData.use_command_reroll(difficulty):
		var decline = {
			"type": "DECLINE_COMMAND_REROLL",
			"actor_unit_id": unit_id,
			"player": player,
			"_ai_description": "AI declines Command Re-roll (difficulty: %s)" % AIDifficultyConfigData.difficulty_name(difficulty)
		}
		_submit_reactive_action(player, decline)
		return

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

	# T7-55: Track reactive action counts for spectator phase summaries
	if _spectator_mode:
		_track_action_for_summary(player, decision.get("type", ""), GameState.get_current_phase())

	# T7-37: Route key reactive decisions through GameEventLog with enhanced reasoning
	var reactive_type = decision.get("type", "")
	if reactive_type in ["USE_REACTIVE_STRATAGEM", "USE_FIRE_OVERWATCH",
			"USE_COUNTER_OFFENSIVE", "USE_HEROIC_INTERVENTION", "USE_TANK_SHOCK"]:
		_log_ai_event(player, description)

	# T7-57: Track CP spent for reactive stratagems
	if reactive_type in ["USE_REACTIVE_STRATAGEM", "USE_FIRE_OVERWATCH",
			"USE_COUNTER_OFFENSIVE", "USE_HEROIC_INTERVENTION", "USE_TANK_SHOCK",
			"USE_COMMAND_REROLL"]:
		var cp_cost = decision.get("cp_cost", 1)
		record_ai_cp_spent(player, cp_cost)
		record_ai_key_moment(player, description)

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

	var difficulty = get_difficulty(player)
	print("AIPlayer: Player %d deciding in phase %d with %d available actions (difficulty: %s)" % [
		player, phase, available.size(), AIDifficultyConfigData.difficulty_name(difficulty)])

	# Ask decision maker what to do
	var decision = AIDecisionMaker.decide(phase, snapshot, available, player, difficulty)

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

	# T7-55: Track action counts for spectator phase summaries
	if _spectator_mode:
		_track_action_for_summary(player, decision.get("type", ""), phase)

	# T7-37: Route key tactical decisions through GameEventLog with enhanced reasoning
	var action_type = decision.get("type", "")
	if action_type in ["SHOOT", "DECLARE_CHARGE", "ASSIGN_ATTACKS", "SELECT_FIGHTER",
			"USE_REACTIVE_STRATAGEM", "USE_FIRE_OVERWATCH", "USE_COUNTER_OFFENSIVE",
			"USE_HEROIC_INTERVENTION", "USE_TANK_SHOCK", "USE_GRENADE_STRATAGEM"]:
		_log_ai_event(player, description)

	# T7-57: Track CP spent for proactive stratagems
	if action_type in ["USE_REACTIVE_STRATAGEM", "USE_FIRE_OVERWATCH",
			"USE_COUNTER_OFFENSIVE", "USE_HEROIC_INTERVENTION", "USE_TANK_SHOCK",
			"USE_GRENADE_STRATAGEM", "USE_COMMAND_REROLL"]:
		var cp_cost = decision.get("cp_cost", 1)
		record_ai_cp_spent(player, cp_cost)
		record_ai_key_moment(player, description)

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

	# T7-21: Capture model origin positions before staging for path visualization
	var origin_positions: Dictionary = {}  # model_id -> Vector2
	var unit_data = GameState.get_unit(unit_id)
	for model in unit_data.get("models", []):
		var mid = model.get("id", "")
		if mid in destinations and model.get("alive", true):
			var pos = model.get("position")
			if pos != null:
				if pos is Dictionary:
					origin_positions[mid] = Vector2(pos.get("x", 0), pos.get("y", 0))
				elif pos is Vector2:
					origin_positions[mid] = pos

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
			# T7-21: Show movement path visualization
			_show_ai_movement_paths(origin_positions, destinations, player)
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

	# T7-21: Capture model origin positions before staging for path visualization
	var origin_positions: Dictionary = {}  # model_id -> Vector2
	var unit_data = GameState.get_unit(unit_id)
	for model in unit_data.get("models", []):
		var mid = model.get("id", "")
		if mid in destinations and model.get("alive", true):
			var pos = model.get("position")
			if pos != null:
				if pos is Dictionary:
					origin_positions[mid] = Vector2(pos.get("x", 0), pos.get("y", 0))
				elif pos is Vector2:
					origin_positions[mid] = pos

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
			# T7-21: Show movement path visualization
			_show_ai_movement_paths(origin_positions, destinations, player)
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

# =============================================================================
# T7-21: AI Movement Path Visualization
# =============================================================================

func _show_ai_movement_paths(origin_positions: Dictionary, destinations: Dictionary, player: int) -> void:
	"""Create an AIMovementPathVisual showing trails from origins to destinations."""
	var board_root = get_node_or_null("/root/Main/BoardRoot")
	if not board_root:
		print("AIPlayer: T7-21: Cannot find BoardRoot for movement path visual")
		return

	var paths: Array = []
	for model_id in destinations:
		if model_id in origin_positions:
			var from_pos: Vector2 = origin_positions[model_id]
			var dest = destinations[model_id]
			var to_pos = Vector2(dest[0], dest[1])
			# Only show trail if model actually moved a meaningful distance
			if from_pos.distance_to(to_pos) > 5.0:
				paths.append({"from": from_pos, "to": to_pos})

	if paths.is_empty():
		return

	var visual = AIMovementPathVisualScript.new()
	visual.name = "AIMovementPathVisual_%d" % (randi() % 10000)
	board_root.add_child(visual)
	visual.show_paths(paths, player)

# =============================================================================
# T7-36: AI Speed Controls
# =============================================================================

func get_ai_speed_preset() -> int:
	"""T7-36: Get the current AI speed preset."""
	return _ai_speed_preset

func get_ai_speed_name() -> String:
	"""T7-36: Get the display name of the current AI speed preset."""
	return AI_SPEED_NAMES.get(_ai_speed_preset, "Normal")

func set_ai_speed_preset(preset: int) -> void:
	"""T7-36: Set the AI speed preset."""
	if preset < 0 or preset > AISpeedPreset.STEP_BY_STEP:
		return
	_ai_speed_preset = preset
	var preset_name = AI_SPEED_NAMES.get(preset, "Normal")
	emit_signal("ai_speed_changed", preset, preset_name)
	# If switching away from step-by-step, unpause
	if preset != AISpeedPreset.STEP_BY_STEP and _step_by_step_paused:
		_step_by_step_paused = false
	print("AIPlayer: T7-36 AI speed set to %s (delay: %.0fms)" % [preset_name, AI_SPEED_DELAYS.get(preset, 0.2) * 1000])

func cycle_ai_speed() -> int:
	"""T7-36: Cycle to the next AI speed preset. Returns the new preset."""
	var next_preset = (_ai_speed_preset + 1) % (AISpeedPreset.STEP_BY_STEP + 1)
	set_ai_speed_preset(next_preset)
	return next_preset

func step_by_step_continue() -> void:
	"""T7-36: Resume AI evaluation in step-by-step mode (called by UI on user input)."""
	if _step_by_step_paused:
		_step_by_step_paused = false
		print("AIPlayer: T7-36 Step-by-step continued by user")

func is_step_by_step_paused() -> bool:
	"""T7-36: Returns true if the AI is paused waiting for user input in step-by-step mode."""
	return _step_by_step_paused

# =============================================================================
# T7-55: Spectator Mode (AI vs AI) Helpers
# =============================================================================

func is_spectator_mode() -> bool:
	"""Returns true when both players are AI (spectator/AI-vs-AI mode)."""
	return _spectator_mode

func get_spectator_speed() -> float:
	"""Get the current spectator speed multiplier."""
	return SPECTATOR_SPEED_PRESETS[_spectator_speed_index]

func set_spectator_speed_index(index: int) -> void:
	"""Set the spectator speed by preset index."""
	_spectator_speed_index = clampi(index, 0, SPECTATOR_SPEED_PRESETS.size() - 1)
	var speed = get_spectator_speed()
	emit_signal("spectator_speed_changed", speed)
	print("AIPlayer: Spectator speed set to %.2fx" % speed)

func cycle_spectator_speed() -> float:
	"""Cycle to the next spectator speed preset. Returns the new speed."""
	_spectator_speed_index = (_spectator_speed_index + 1) % SPECTATOR_SPEED_PRESETS.size()
	var speed = get_spectator_speed()
	emit_signal("spectator_speed_changed", speed)
	print("AIPlayer: Spectator speed cycled to %.2fx" % speed)
	return speed

func _get_effective_action_delay() -> float:
	"""Get the action delay, accounting for AI speed preset and spectator mode."""
	if not _spectator_mode:
		# T7-36: Use configured speed preset delay
		return AI_SPEED_DELAYS.get(_ai_speed_preset, 0.2)
	var speed = get_spectator_speed()
	return SPECTATOR_ACTION_DELAY / speed

func _track_action_for_summary(player: int, action_type: String, phase: int) -> void:
	"""Track an action for the spectator phase summary."""
	var key = str(player) + "_" + str(phase)
	if not _phase_action_counts.has(key):
		_phase_action_counts[key] = {}
	var counts = _phase_action_counts[key]

	# Group actions into readable categories
	var category = _categorize_action(action_type)
	if category != "":
		counts[category] = counts.get(category, 0) + 1

func _categorize_action(action_type: String) -> String:
	"""Map action types to readable summary categories."""
	match action_type:
		"DEPLOY_UNIT":
			return "units_deployed"
		"REMAIN_STATIONARY":
			return "units_stationary"
		"CONFIRM_UNIT_MOVE", "BEGIN_NORMAL_MOVE":
			return "units_moved"
		"BEGIN_ADVANCE":
			return "units_advanced"
		"BEGIN_FALL_BACK":
			return "units_fell_back"
		"SHOOT", "USE_THROAT_SLITTAS":
			return "units_shot"
		"DECLARE_CHARGE":
			return "charges_declared"
		"SELECT_FIGHTER", "ASSIGN_ATTACKS":
			return "units_fought"
		"USE_REACTIVE_STRATAGEM", "USE_FIRE_OVERWATCH", "USE_COUNTER_OFFENSIVE", \
		"USE_HEROIC_INTERVENTION", "USE_TANK_SHOCK", "USE_GRENADE_STRATAGEM", \
		"USE_COMMAND_REROLL", "USE_RAPID_INGRESS":
			return "stratagems_used"
		"PLACE_RAPID_INGRESS_REINFORCEMENT":
			return "reinforcements"
		"SKIP_UNIT", "SKIP_CHARGE":
			return "units_skipped"
		"PLACE_REINFORCEMENT":
			return "reinforcements"
		_:
			return ""

func _emit_phase_summary_for_current_phase() -> void:
	"""Emit a phase summary for each player that acted in the current phase."""
	var current_phase_val = GameState.get_current_phase()
	for player in [1, 2]:
		var key = str(player) + "_" + str(current_phase_val)
		if _phase_action_counts.has(key) and not _phase_action_counts[key].is_empty():
			var summary = _phase_action_counts[key].duplicate()
			emit_signal("spectator_phase_summary", player, current_phase_val, summary)
			print("AIPlayer: Spectator phase summary for P%d phase %d: %s" % [player, current_phase_val, str(summary)])
	# Clear counts for the completed phase
	var keys_to_remove = []
	for key in _phase_action_counts:
		if key.ends_with("_" + str(current_phase_val)):
			keys_to_remove.append(key)
	for key in keys_to_remove:
		_phase_action_counts.erase(key)

# =============================================================================
# T7-57: Post-Game Performance Tracking Signal Handlers
# =============================================================================

func _on_vp_scored(player: int, points: int, reason: String) -> void:
	"""T7-57: Track VP scoring as key moments for AI players."""
	if not is_ai_player(player) or points <= 0:
		return
	record_ai_key_moment(player, "Scored %d VP (%s)" % [points, reason])

# =============================================================================
# T7-57: Post-Game Performance Summary
# =============================================================================

func record_ai_cp_spent(player: int, amount: int) -> void:
	"""T7-57: Record CP spent by an AI player."""
	if _game_performance.has(player):
		_game_performance[player]["cp_spent"] += amount
		print("AIPlayer: T7-57 P%d CP spent +%d (total: %d)" % [player, amount, _game_performance[player]["cp_spent"]])

func record_ai_unit_killed(player: int) -> void:
	"""T7-57: Record that an AI player destroyed an enemy unit."""
	if _game_performance.has(player):
		_game_performance[player]["units_killed"] += 1
		print("AIPlayer: T7-57 P%d units killed: %d" % [player, _game_performance[player]["units_killed"]])

func record_ai_unit_lost(player: int) -> void:
	"""T7-57: Record that an AI player lost a unit."""
	if _game_performance.has(player):
		_game_performance[player]["units_lost"] += 1
		print("AIPlayer: T7-57 P%d units lost: %d" % [player, _game_performance[player]["units_lost"]])

func record_ai_objectives(player: int, battle_round: int, count: int) -> void:
	"""T7-57: Record objectives held by an AI player at end of a scoring phase."""
	if _game_performance.has(player):
		_game_performance[player]["objectives_per_round"][battle_round] = count
		print("AIPlayer: T7-57 P%d held %d objectives in round %d" % [player, count, battle_round])

func record_ai_key_moment(player: int, text: String) -> void:
	"""T7-57: Record a key moment for the AI performance summary."""
	if _game_performance.has(player):
		var moment = {
			"round": GameState.get_battle_round(),
			"text": text,
		}
		_game_performance[player]["key_moments"].append(moment)
		print("AIPlayer: T7-57 P%d key moment (R%d): %s" % [player, moment.round, text])

func get_performance_summary() -> Dictionary:
	"""T7-57: Build a complete post-game performance summary for all AI players.
	Returns {player_id -> {vp_total, vp_primary, vp_secondary, cp_spent, cp_remaining,
	units_lost, units_killed, objectives_per_round, key_moments, difficulty}}."""
	var summary = {}

	for player in _game_performance:
		var perf = _game_performance[player]
		var player_key = str(player)

		# VP data from GameState
		var vp_data = GameState.state.get("players", {}).get(player_key, {})
		var vp_total = vp_data.get("vp", 0)
		var vp_primary = vp_data.get("primary_vp", 0)
		var vp_secondary = vp_data.get("secondary_vp", 0)
		var cp_remaining = vp_data.get("cp", 0)

		# Unit counts from current game state
		var units_remaining = 0
		var total_models_remaining = 0
		var total_models_starting = 0
		for unit_id in GameState.state.get("units", {}):
			var unit = GameState.state.units[unit_id]
			if unit.get("owner", 0) != player:
				continue
			var models = unit.get("models", [])
			total_models_starting += models.size()
			var alive_count = 0
			for model in models:
				if model.get("alive", true):
					alive_count += 1
			if alive_count > 0:
				units_remaining += 1
			total_models_remaining += alive_count

		# Difficulty name
		var diff = ai_difficulty.get(player, AIDifficultyConfigData.Difficulty.NORMAL)
		var diff_name = AIDifficultyConfigData.difficulty_name(diff)

		# Faction name
		var faction_name = GameState.get_faction_name(player)

		summary[player] = {
			"faction": faction_name,
			"difficulty": diff_name,
			"vp_total": vp_total,
			"vp_primary": vp_primary,
			"vp_secondary": vp_secondary,
			"cp_spent": perf.get("cp_spent", 0),
			"cp_remaining": cp_remaining,
			"units_killed": perf.get("units_killed", 0),
			"units_lost": perf.get("units_lost", 0),
			"units_remaining": units_remaining,
			"models_remaining": total_models_remaining,
			"models_starting": total_models_starting,
			"objectives_per_round": perf.get("objectives_per_round", {}),
			"key_moments": perf.get("key_moments", []),
		}

	print("AIPlayer: T7-57 Performance summary built for %d AI player(s)" % summary.size())
	return summary

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
