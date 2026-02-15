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

# Signals for UI
signal ai_turn_started(player: int)
signal ai_turn_ended(player: int, action_summary: Array)
signal ai_action_taken(player: int, action: Dictionary, description: String)

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

	print("AIPlayer: Ready (disabled until configured)")

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
		call_deferred("_evaluate_and_act")

func is_ai_player(player: int) -> bool:
	return enabled and ai_players.get(player, false)

func get_action_log() -> Array:
	return _action_log.duplicate()

func clear_action_log() -> void:
	_action_log.clear()

# --- Signal handlers ---

func _on_phase_changed(_new_phase) -> void:
	if not enabled:
		return
	_current_phase_actions = 0  # Reset safety counter on phase change
	call_deferred("_evaluate_and_act")

func _on_result_applied(_result: Dictionary) -> void:
	if not enabled:
		return
	# After any action result, check if AI should act next
	call_deferred("_evaluate_and_act")

func _on_phase_action_taken(_action: Dictionary) -> void:
	if not enabled:
		return
	# After any phase action, check if AI should act next
	# This is the primary trigger in single-player mode
	call_deferred("_evaluate_and_act")

# --- Core AI loop ---

func _evaluate_and_act() -> void:
	if _processing_turn:
		return  # Already processing, avoid re-entrancy

	var active_player = GameState.get_active_player()
	if not is_ai_player(active_player):
		return  # Not AI's turn

	var phase_manager = get_node_or_null("/root/PhaseManager")
	if not phase_manager:
		return
	if not phase_manager.current_phase_instance:
		return  # No active phase

	# Check game completion
	if GameState.is_game_complete():
		print("AIPlayer: Game is complete, not acting")
		return

	# Safety check - prevent infinite action loops
	if _current_phase_actions >= MAX_ACTIONS_PER_PHASE:
		push_error("AIPlayer: Hit max actions (%d) for current phase! Stopping to prevent infinite loop." % MAX_ACTIONS_PER_PHASE)
		return

	_processing_turn = true
	_execute_next_action(active_player)
	_processing_turn = false

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
