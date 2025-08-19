extends Node

# PhaseManager - Orchestrates phase transitions and manages the current active phase
# This is the central controller for the modular phase system

signal phase_changed(new_phase: GameStateData.Phase)
signal phase_completed(phase: GameStateData.Phase)
signal phase_action_taken(action: Dictionary)

var current_phase_instance: BasePhase = null
var phase_classes: Dictionary = {}

func _ready() -> void:
	# Register all available phase classes
	register_phase_classes()
	
	# Start with deployment phase
	transition_to_phase(GameStateData.Phase.DEPLOYMENT)

func register_phase_classes() -> void:
	# Register phase implementations
	phase_classes[GameStateData.Phase.DEPLOYMENT] = preload("res://phases/DeploymentPhase.gd")
	phase_classes[GameStateData.Phase.MOVEMENT] = preload("res://phases/MovementPhase.gd")
	phase_classes[GameStateData.Phase.SHOOTING] = preload("res://phases/ShootingPhase.gd")
	phase_classes[GameStateData.Phase.CHARGE] = preload("res://phases/ChargePhase.gd")
	phase_classes[GameStateData.Phase.FIGHT] = preload("res://phases/FightPhase.gd")
	phase_classes[GameStateData.Phase.MORALE] = preload("res://phases/MoralePhase.gd")

func transition_to_phase(new_phase: GameStateData.Phase) -> void:
	# Exit current phase if one exists
	if current_phase_instance != null:
		current_phase_instance.exit_phase()
		current_phase_instance.queue_free()
		current_phase_instance = null
	
	# Update game state to new phase
	GameState.set_phase(new_phase)
	
	# Create and initialize new phase instance
	if phase_classes.has(new_phase):
		current_phase_instance = phase_classes[new_phase].new()
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
		current_phase_instance.enter_phase(GameState.create_snapshot())
		
		emit_signal("phase_changed", new_phase)
	else:
		push_error("No implementation found for phase: " + str(new_phase))

func get_current_phase() -> GameStateData.Phase:
	return GameState.get_current_phase()

func get_current_phase_instance() -> BasePhase:
	return current_phase_instance

func advance_to_next_phase() -> void:
	var current = get_current_phase()
	var next_phase = _get_next_phase(current)
	
	if next_phase != current:
		transition_to_phase(next_phase)
	else:
		# End of turn, advance turn and start with deployment
		GameState.advance_turn()
		transition_to_phase(GameStateData.Phase.DEPLOYMENT)

func _get_next_phase(current: GameStateData.Phase) -> GameStateData.Phase:
	# Define the standard 40k phase order
	match current:
		GameStateData.Phase.DEPLOYMENT:
			return GameStateData.Phase.MOVEMENT
		GameStateData.Phase.MOVEMENT:
			return GameStateData.Phase.SHOOTING
		GameStateData.Phase.SHOOTING:
			return GameStateData.Phase.CHARGE
		GameStateData.Phase.CHARGE:
			return GameStateData.Phase.FIGHT
		GameStateData.Phase.FIGHT:
			return GameStateData.Phase.MORALE
		GameStateData.Phase.MORALE:
			return GameStateData.Phase.DEPLOYMENT  # Next turn
		_:
			return GameStateData.Phase.DEPLOYMENT

func _on_phase_completed() -> void:
	var completed_phase = get_current_phase()
	
	# Commit current phase log to history before transitioning
	GameState.commit_phase_log_to_history()
	
	emit_signal("phase_completed", completed_phase)
	
	# Advance to next phase
	advance_to_next_phase()

func _on_phase_action_taken(action: Dictionary) -> void:
	# Record action in phase log
	GameState.add_action_to_phase_log(action)
	
	emit_signal("phase_action_taken", action)

# Utility methods for phases to interact with game state
func get_game_state_snapshot() -> Dictionary:
	return GameState.create_snapshot()

func apply_state_changes(changes: Array) -> void:
	# Apply an array of state changes atomically
	for change in changes:
		_apply_single_change(change)

func _apply_single_change(change: Dictionary) -> void:
	# Apply a single state change based on operation type
	match change.get("op", ""):
		"set":
			_set_state_value(change.path, change.value)
		"add":
			_add_to_state_array(change.path, change.value)
		"remove":
			_remove_from_state_array(change.path, change.index)
		_:
			push_error("Unknown state change operation: " + str(change.get("op", "")))

func _set_state_value(path: String, value) -> void:
	var parts = path.split(".")
	if parts.is_empty():
		return
	
	var current = GameState.state
	for i in range(parts.size() - 1):
		var part = parts[i]
		if part.is_valid_int():
			var index = part.to_int()
			if current is Array and index >= 0 and index < current.size():
				current = current[index]
			else:
				return
		else:
			if current is Dictionary and current.has(part):
				current = current[part]
			else:
				return
	
	var final_key = parts[-1]
	if final_key.is_valid_int():
		var index = final_key.to_int()
		if current is Array and index >= 0 and index < current.size():
			current[index] = value
	else:
		if current is Dictionary:
			current[final_key] = value

func _add_to_state_array(path: String, value) -> void:
	var parts = path.split(".")
	var current = GameState.state
	
	for part in parts:
		if part.is_valid_int():
			var index = part.to_int()
			if current is Array and index >= 0 and index < current.size():
				current = current[index]
			else:
				return
		else:
			if current is Dictionary and current.has(part):
				current = current[part]
			else:
				return
	
	if current is Array:
		current.append(value)

func _remove_from_state_array(path: String, index: int) -> void:
	var parts = path.split(".")
	var current = GameState.state
	
	for part in parts:
		if part.is_valid_int():
			var array_index = part.to_int()
			if current is Array and array_index >= 0 and array_index < current.size():
				current = current[array_index]
			else:
				return
		else:
			if current is Dictionary and current.has(part):
				current = current[part]
			else:
				return
	
	if current is Array and index >= 0 and index < current.size():
		current.remove_at(index)

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
