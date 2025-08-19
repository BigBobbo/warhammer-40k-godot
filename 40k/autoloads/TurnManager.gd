extends Node

# TurnManager - Manages turn flow and phase transitions using the new modular system
# Now works with PhaseManager and GameState instead of BoardState

signal deployment_side_changed(player: int)
signal deployment_phase_complete()
signal turn_advanced(turn_number: int)
signal phase_transition_requested(from_phase: GameStateData.Phase, to_phase: GameStateData.Phase)

func _ready() -> void:
	# Connect to PhaseManager
	if has_node("/root/PhaseManager"):
		var phase_manager = get_node("/root/PhaseManager")
		phase_manager.phase_completed.connect(_on_phase_completed)
		phase_manager.phase_changed.connect(_on_phase_changed)
		phase_manager.phase_action_taken.connect(_on_phase_action_taken)

func _on_phase_completed(completed_phase: GameStateData.Phase) -> void:
	match completed_phase:
		GameStateData.Phase.DEPLOYMENT:
			emit_signal("deployment_phase_complete")
		GameStateData.Phase.MORALE:
			# End of turn, advance turn number
			var new_turn = GameState.get_turn_number() + 1
			GameState.advance_turn()
			emit_signal("turn_advanced", new_turn)

func _on_phase_changed(new_phase: GameStateData.Phase) -> void:
	match new_phase:
		GameStateData.Phase.DEPLOYMENT:
			_handle_deployment_phase_start()

func _on_phase_action_taken(action: Dictionary) -> void:
	var action_type = action.get("type", "")
	var current_phase = GameState.get_current_phase()
	
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			if action_type == "DEPLOY_UNIT":
				check_deployment_alternation()

# Deployment phase management (backwards compatibility)
func check_deployment_alternation() -> void:
	var player1_has_units = _has_undeployed_units(1)
	var player2_has_units = _has_undeployed_units(2)
	
	if not player1_has_units and not player2_has_units:
		# All units deployed - phase will complete automatically
		return
	
	var current_player = GameState.get_active_player()
	
	# Simple alternation - if both players have units, just alternate every time
	if player1_has_units and player2_has_units:
		alternate_active_player()
	# If only one player has units left, switch to that player if needed
	elif player1_has_units and current_player != 1:
		_set_active_player(1)
	elif player2_has_units and current_player != 2:
		_set_active_player(2)

func alternate_active_player() -> void:
	var current_player = GameState.get_active_player()
	var new_player = 2 if current_player == 1 else 1
	_set_active_player(new_player)

func _set_active_player(player: int) -> void:
	GameState.set_active_player(player)
	emit_signal("deployment_side_changed", player)

func _handle_deployment_phase_start() -> void:
	# Set initial active player for deployment
	var player1_has_units = _has_undeployed_units(1)
	var player2_has_units = _has_undeployed_units(2)
	
	if player1_has_units:
		_set_active_player(1)
	elif player2_has_units:
		_set_active_player(2)

# Helper methods using new GameState system
func _has_undeployed_units(player: int) -> bool:
	var undeployed_units = GameState.get_undeployed_units_for_player(player)
	return undeployed_units.size() > 0

# Backwards compatibility methods
func start_deployment_phase() -> void:
	if has_node("/root/PhaseManager"):
		get_node("/root/PhaseManager").transition_to_phase(GameStateData.Phase.DEPLOYMENT)
	else:
		# Fallback - set initial state in GameState
		GameState.set_phase(GameStateData.Phase.DEPLOYMENT)
		GameState.set_active_player(1)
		emit_signal("deployment_side_changed", 1)

# Removed old GameManager compatibility - now using PhaseManager exclusively

# Phase transition interface
func request_phase_transition(to_phase: GameStateData.Phase) -> void:
	var current_phase = GameState.get_current_phase()
	emit_signal("phase_transition_requested", current_phase, to_phase)
	
	if has_node("/root/PhaseManager"):
		get_node("/root/PhaseManager").transition_to_phase(to_phase)

func advance_to_next_phase() -> void:
	if has_node("/root/PhaseManager"):
		get_node("/root/PhaseManager").advance_to_next_phase()

func get_current_phase() -> GameStateData.Phase:
	return GameState.get_current_phase()

func get_current_turn() -> int:
	return GameState.get_turn_number()

func get_active_player() -> int:
	return GameState.get_active_player()

# Advanced turn management
func can_advance_phase() -> bool:
	var current_phase = get_current_phase()
	
	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			return GameState.all_units_deployed()
		_:
			# For other phases, delegate to PhaseManager
			if has_node("/root/PhaseManager"):
				var phase_manager = get_node("/root/PhaseManager")
				if phase_manager.current_phase_instance:
					var phase_instance = phase_manager.current_phase_instance
					if phase_instance.has_method("_should_complete_phase"):
						return phase_instance._should_complete_phase()
			return false

func force_phase_completion() -> void:
	if has_node("/root/PhaseManager"):
		var phase_manager = get_node("/root/PhaseManager")
		if phase_manager.current_phase_instance:
			phase_manager.current_phase_instance.emit_signal("phase_completed")

# Game state queries
func get_game_status() -> Dictionary:
	return {
		"turn": get_current_turn(),
		"phase": get_current_phase(),
		"active_player": get_active_player(),
		"can_advance_phase": can_advance_phase(),
		"deployment_complete": GameState.all_units_deployed(),
		"game_id": GameState.state.get("meta", {}).get("game_id", "")
	}

# Debug methods
func print_turn_status() -> void:
	var status = get_game_status()
	print("=== Turn Status ===")
	print("Turn: %d" % status.turn)
	print("Phase: %s" % str(status.phase))
	print("Active Player: %d" % status.active_player)
	print("Can Advance Phase: %s" % str(status.can_advance_phase))
	print("Deployment Complete: %s" % str(status.deployment_complete))