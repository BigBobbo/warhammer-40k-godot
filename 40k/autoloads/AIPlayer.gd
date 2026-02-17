extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# AIPlayer - Autoload controller for AI opponents
# Monitors game signals and submits actions through NetworkIntegration.route_action()
# when the active player is configured as AI.

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
		var phase_manager = get_node("/root/PhaseManager")
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

# --- Core AI loop ---

func _evaluate_and_act() -> void:
	if not enabled or PhaseManager.game_ended:
		return

	DebugLogger.info("AIPlayer._evaluate_and_act called", {"processing_turn": _processing_turn, "enabled": enabled})
	if _processing_turn:
		DebugLogger.info("AIPlayer._evaluate_and_act - skipped (already processing)", {})
		return  # Already processing, avoid re-entrancy

	var active_player = GameState.get_active_player()
	if not is_ai_player(active_player):
		DebugLogger.info("AIPlayer._evaluate_and_act - not AI turn", {"active_player": active_player})
		return  # Not AI's turn

	var phase_manager = get_node_or_null("/root/PhaseManager")
	if not phase_manager:
		DebugLogger.info("AIPlayer._evaluate_and_act - no PhaseManager", {})
		return
	if not phase_manager.current_phase_instance:
		DebugLogger.info("AIPlayer._evaluate_and_act - no phase instance", {})
		return  # No active phase

	# Check game completion
	if GameState.is_game_complete():
		if enabled:
			print("AIPlayer: Game is complete, disabling AI")
			enabled = false
		return

	# Safety check - prevent infinite action loops
	if _current_phase_actions >= MAX_ACTIONS_PER_PHASE:
		push_error("AIPlayer: Hit max actions (%d) for current phase! Stopping to prevent infinite loop." % MAX_ACTIONS_PER_PHASE)
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
		return

	print("AIPlayer: Player %d deciding in phase %d with %d available actions" % [player, phase, available.size()])

	# Ask decision maker what to do
	var decision = AIDecisionMaker.decide(phase, snapshot, available, player)

	if decision.is_empty():
		push_warning("AIPlayer: No decision made for player %d in phase %d" % [player, phase])
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

		# Handle multi-step movement: BEGIN_NORMAL_MOVE with pre-computed destinations
		elif decision.get("type") == "BEGIN_NORMAL_MOVE" and decision.has("_ai_model_destinations"):
			_execute_ai_movement(player, decision)

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
