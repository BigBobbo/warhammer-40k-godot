extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# TurnManager - Manages turn flow and phase transitions using the new modular system
# Now works with PhaseManager and GameState instead of BoardState

signal deployment_side_changed(player: int)
signal deployment_phase_complete()
signal turn_advanced(turn_number: int)
signal battle_round_advanced(round: int)
signal phase_transition_requested(from_phase: GameStateData.Phase, to_phase: GameStateData.Phase)

# Tracks pending deployment turn skips due to TITANIC unit deployment
# Key: player number (1 or 2), Value: number of skips remaining
var _titanic_skip_turns: Dictionary = {}

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
			_titanic_skip_turns.clear()
			emit_signal("deployment_phase_complete")
		GameStateData.Phase.SCOUT:
			# Scout phase complete - roll-off phase will determine who goes first
			print("TurnManager: Scout phase complete, advancing to Roll-Off phase")
		GameStateData.Phase.ROLL_OFF:
			# Roll-off phase complete - active player was set by the roll-off choice
			var first_turn_player = GameState.state.get("meta", {}).get("first_turn_player", 1)
			print("TurnManager: Roll-off complete, Player %d takes the first turn" % first_turn_player)
		GameStateData.Phase.SCORING:
			# Scoring phase handles player switching and battle round advancement
			# Check if battle round was advanced during scoring phase
			var current_battle_round = GameState.get_battle_round()
			var current_player = GameState.get_active_player()

			# If we're at player 1 after scoring, battle round was advanced
			if current_player == 1:
				print("TurnManager: Battle round advanced to ", current_battle_round)
				emit_signal("battle_round_advanced", current_battle_round)

				# Check for game end
				if GameState.is_game_complete():
					print("TurnManager: Game completed after 5 battle rounds!")

			print("TurnManager: Player turn switched to Player ", current_player)
		GameStateData.Phase.MORALE:
			# End of turn, advance turn number
			var new_turn = GameState.get_turn_number() + 1
			GameState.advance_turn()
			emit_signal("turn_advanced", new_turn)

func _on_phase_changed(new_phase: GameStateData.Phase) -> void:
	match new_phase:
		GameStateData.Phase.FORMATIONS:
			# Formations phase starts with Player 1
			_set_active_player(1)
		GameStateData.Phase.DEPLOYMENT:
			_titanic_skip_turns.clear()
			_handle_deployment_phase_start()

func _on_phase_action_taken(action: Dictionary) -> void:
	var action_type = action.get("type", "")
	var current_phase = GameState.get_current_phase()

	print("[TurnManager] Received action: ", action_type)
	print("[TurnManager] Current phase: ", current_phase)

	match current_phase:
		GameStateData.Phase.DEPLOYMENT:
			# All deployment actions that resolve a unit should alternate the active player.
			# DEPLOY_UNIT: unit placed on the board
			# COMPOSITE_DEPLOY: atomic deploy + embark/attach (P2-43)
			# PLACE_IN_RESERVES: unit placed in Strategic Reserves or Deep Strike
			# EMBARK_UNITS_DEPLOYMENT: unit(s) embarked in a transport (counts as deployed)
			# ATTACH_CHARACTER_DEPLOYMENT: character attached to a bodyguard (counts as deployed)
			if action_type in ["DEPLOY_UNIT", "COMPOSITE_DEPLOY", "PLACE_IN_RESERVES", "EMBARK_UNITS_DEPLOYMENT", "ATTACH_CHARACTER_DEPLOYMENT"]:
				var deployed_unit_id = action.get("unit_id", "")
				print("[TurnManager] Processing %s action" % action_type)
				print("[TurnManager] Unit: ", deployed_unit_id if deployed_unit_id else "Unknown")
				# Switch players after each deployment action
				check_deployment_alternation(deployed_unit_id)

# Deployment phase management (backwards compatibility)
func check_deployment_alternation(last_deployed_unit_id: String = "") -> void:
	var player1_has_units = _has_undeployed_units(1)
	var player2_has_units = _has_undeployed_units(2)

	print("[TurnManager] Player 1 has undeployed units: ", player1_has_units)
	print("[TurnManager] Player 2 has undeployed units: ", player2_has_units)

	if not player1_has_units and not player2_has_units:
		print("[TurnManager] All units deployed - phase will complete")
		# All units deployed - phase will complete automatically
		return

	var current_player = GameState.get_active_player()
	print("[TurnManager] Current active player: ", current_player)

	# 10e Rule: When a player sets up a TITANIC unit, they skip their next
	# deployment turn. Check if the just-deployed unit has the TITANIC keyword
	# and flag the deploying player to be skipped.
	# Only applies to units placed on the board (DEPLOYED status), not reserves.
	if last_deployed_unit_id != "":
		var deployed_unit = GameState.get_unit(last_deployed_unit_id)
		var unit_status = deployed_unit.get("status", -1)
		# Only trigger TITANIC skip for units actually set up on the board
		if unit_status != GameStateData.UnitStatus.IN_RESERVES:
			var keywords = deployed_unit.get("meta", {}).get("keywords", [])
			if "TITANIC" in keywords:
				var deploying_player = deployed_unit.get("owner", current_player)
				_titanic_skip_turns[deploying_player] = _titanic_skip_turns.get(deploying_player, 0) + 1
				var unit_name = deployed_unit.get("meta", {}).get("name", last_deployed_unit_id)
				print("[TurnManager] TITANIC unit '%s' set up by Player %d - Player %d skips next deployment turn" % [unit_name, deploying_player, deploying_player])

	# Simple alternation - if both players have units, just alternate every time
	if player1_has_units and player2_has_units:
		print("[TurnManager] Both players have units - alternating")
		alternate_active_player()
		# After alternating, check if the now-active player should be skipped
		# due to opponent's TITANIC deployment
		_apply_titanic_skips()
	# If only one player has units left, switch to that player if needed
	elif player1_has_units and current_player != 1:
		print("[TurnManager] Only Player 1 has units - switching to Player 1")
		_set_active_player(1)
		# Clear any pending skips since only one player has units left
		_titanic_skip_turns.clear()
	elif player2_has_units and current_player != 2:
		print("[TurnManager] Only Player 2 has units - switching to Player 2")
		_set_active_player(2)
		# Clear any pending skips since only one player has units left
		_titanic_skip_turns.clear()

# Apply TITANIC deployment skip: if the now-active player has a pending skip,
# consume it and alternate again (giving the opponent an extra deployment turn).
func _apply_titanic_skips() -> void:
	var active_player = GameState.get_active_player()
	var skips = _titanic_skip_turns.get(active_player, 0)
	if skips > 0:
		# Only skip if the active player still has units to deploy
		if _has_undeployed_units(active_player):
			_titanic_skip_turns[active_player] = skips - 1
			print("[TurnManager] TITANIC skip: Player %d's deployment turn skipped (remaining skips: %d)" % [active_player, skips - 1])
			var opponent = 2 if active_player == 1 else 1
			if _has_undeployed_units(opponent):
				# Opponent gets an extra turn — skip back to them
				alternate_active_player()
			else:
				# Opponent has no units — skip is moot, stay on active player
				print("[TurnManager] TITANIC skip: opponent has no units, skip is moot")
				_titanic_skip_turns[active_player] = 0
		else:
			# Active player has no units to skip — clear the skip
			_titanic_skip_turns[active_player] = 0

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
