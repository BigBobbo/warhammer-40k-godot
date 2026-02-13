extends BasePhase
class_name ScoutMovesPhase

const BasePhase = preload("res://phases/BasePhase.gd")

# ScoutMovesPhase - Handles the Scout Moves sub-phase between Deployment and Command
# Per 10th Edition rules:
# - After deployment is complete, before the first battle round
# - Units with "Scout X\"" can make a Normal Move of up to X inches
# - Must end >9" from all enemy models (edge-to-edge)
# - The player who takes the first turn moves their Scout units first
# - Dedicated Transports inherit Scout if all embarked models have it
# - Each unit can only scout once

signal scout_move_begun(unit_id: String, max_inches: float)
signal scout_move_confirmed(unit_id: String)
signal scout_phase_player_done(player: int)

const PX_PER_INCH: float = 40.0
const MIN_ENEMY_DISTANCE_INCHES: float = 9.0

# Track which units have completed their scout move
var scouted_units: Dictionary = {}  # unit_id -> true
var active_scout_move: Dictionary = {}  # Current unit being scouted: {unit_id, max_inches, original_positions}
var current_scout_player: int = 1  # Which player is currently scouting
var scout_player_order: Array = []  # [first_player, second_player]
var phase_done: bool = false

func _init():
	phase_type = GameStateData.Phase.SCOUT_MOVES

func _on_phase_enter() -> void:
	log_phase_message("Entering Scout Moves Phase")
	scouted_units.clear()
	active_scout_move.clear()
	phase_done = false

	# Per rules: the player who takes the first turn moves their Scout units first
	# Currently Player 1 goes first (no roll-off implemented yet)
	var first_player = GameState.get_active_player()
	scout_player_order = [first_player, 3 - first_player]
	current_scout_player = first_player

	# Set active player to the first scout player
	GameState.set_active_player(current_scout_player)

	# Check if any units have Scout ability at all
	var p1_scouts = GameState.get_scout_units_for_player(1)
	var p2_scouts = GameState.get_scout_units_for_player(2)

	print("[ScoutMovesPhase] Player 1 scout units: ", p1_scouts)
	print("[ScoutMovesPhase] Player 2 scout units: ", p2_scouts)

	if p1_scouts.is_empty() and p2_scouts.is_empty():
		# No units have Scout - skip this phase entirely
		log_phase_message("No units with Scout ability - skipping Scout Moves phase")
		phase_done = true
		emit_signal("phase_completed")
		return

	# If the first player has no scouts, skip to second player
	var first_scouts = GameState.get_scout_units_for_player(current_scout_player)
	if first_scouts.is_empty():
		_advance_to_next_scout_player()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Scout Moves Phase")
	active_scout_move.clear()

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	# Check base phase validation first (handles DEBUG_MOVE)
	var base_validation = super.validate_action(action)
	if not base_validation.get("valid", true):
		return base_validation

	match action_type:
		"BEGIN_SCOUT_MOVE":
			return _validate_begin_scout_move(action)
		"SET_SCOUT_MODEL_DEST":
			return _validate_set_scout_model_dest(action)
		"CONFIRM_SCOUT_MOVE":
			return _validate_confirm_scout_move(action)
		"SKIP_SCOUT_UNIT":
			return _validate_skip_scout_unit(action)
		"END_SCOUT_MOVES":
			return _validate_end_scout_moves(action)
		_:
			return {"valid": false, "errors": ["Unknown action type for Scout Moves phase: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	match action_type:
		"BEGIN_SCOUT_MOVE":
			return _process_begin_scout_move(action)
		"SET_SCOUT_MODEL_DEST":
			return _process_set_scout_model_dest(action)
		"CONFIRM_SCOUT_MOVE":
			return _process_confirm_scout_move(action)
		"SKIP_SCOUT_UNIT":
			return _process_skip_scout_unit(action)
		"END_SCOUT_MOVES":
			return _process_end_scout_moves(action)
		_:
			return create_result(false, [], "Unknown action: " + action_type)

func get_available_actions() -> Array:
	var actions = []
	var player = get_current_player()

	if phase_done:
		return actions

	# If there's an active scout move, only allow model destination or confirm/cancel
	if not active_scout_move.is_empty():
		actions.append({"type": "SET_SCOUT_MODEL_DEST", "unit_id": active_scout_move.unit_id})
		actions.append({"type": "CONFIRM_SCOUT_MOVE", "unit_id": active_scout_move.unit_id})
		return actions

	# Otherwise, allow beginning a scout move or skipping
	var scout_units = GameState.get_scout_units_for_player(player)
	for unit_id in scout_units:
		if not scouted_units.has(unit_id):
			actions.append({"type": "BEGIN_SCOUT_MOVE", "unit_id": unit_id})
			actions.append({"type": "SKIP_SCOUT_UNIT", "unit_id": unit_id})

	# Allow ending scout moves for this player
	actions.append({"type": "END_SCOUT_MOVES", "player": player})

	return actions

# ============================================================================
# VALIDATION
# ============================================================================

func _validate_begin_scout_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}

	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	if not GameState.unit_has_scout(unit_id):
		return {"valid": false, "errors": ["Unit does not have Scout ability"]}

	if scouted_units.has(unit_id):
		return {"valid": false, "errors": ["Unit has already scouted this phase"]}

	if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
		return {"valid": false, "errors": ["Unit must be deployed to scout"]}

	if not active_scout_move.is_empty():
		return {"valid": false, "errors": ["Another scout move is already in progress"]}

	return {"valid": true, "errors": []}

func _validate_set_scout_model_dest(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	if active_scout_move.is_empty() or active_scout_move.get("unit_id", "") != unit_id:
		return {"valid": false, "errors": ["No active scout move for unit: " + unit_id]}

	var model_index = action.get("model_index", -1)
	if model_index < 0:
		return {"valid": false, "errors": ["Invalid model_index"]}

	var dest = action.get("destination", null)
	if dest == null:
		return {"valid": false, "errors": ["Missing destination"]}

	# Validate destination is within scout range of original position
	var original_pos = active_scout_move.original_positions[model_index]
	if original_pos == null:
		return {"valid": false, "errors": ["Model has no original position"]}

	var dx = float(dest.get("x", 0)) - float(original_pos.get("x", 0))
	var dy = float(dest.get("y", 0)) - float(original_pos.get("y", 0))
	var distance_px = sqrt(dx * dx + dy * dy)
	var distance_inches = distance_px / PX_PER_INCH

	var max_inches = active_scout_move.get("max_inches", 0)
	if distance_inches > max_inches + 0.01:  # Small tolerance
		return {"valid": false, "errors": ["Scout move exceeds maximum range of %d\"" % int(max_inches)]}

	# Validate >9" from all enemy models (edge-to-edge)
	var unit = get_unit(unit_id)
	var model = unit.get("models", [])[model_index]
	var model_base_mm = model.get("base_mm", 32)
	var model_base_inches = model_base_mm / 25.4
	var player = unit.get("owner", 0)
	var enemy_positions = GameState.get_enemy_model_positions(player)

	for enemy in enemy_positions:
		var ex = float(enemy.get("x", 0))
		var ey = float(enemy.get("y", 0))
		var enemy_base_mm = enemy.get("base_mm", 32)
		var enemy_base_inches = enemy_base_mm / 25.4

		var edx = float(dest.get("x", 0)) - ex
		var edy = float(dest.get("y", 0)) - ey
		var center_dist_px = sqrt(edx * edx + edy * edy)
		var center_dist_inches = center_dist_px / PX_PER_INCH

		# Edge-to-edge distance = center-to-center - both radii
		var edge_dist = center_dist_inches - (model_base_inches / 2.0) - (enemy_base_inches / 2.0)
		if edge_dist < MIN_ENEMY_DISTANCE_INCHES - 0.01:  # Small tolerance
			return {"valid": false, "errors": ["Scout move must end >9\" from enemy models (current: %.1f\")" % edge_dist]}

	# Validate destination is on the board
	var board = game_state_snapshot.get("board", {})
	var board_width = board.get("size", {}).get("width", 44) * PX_PER_INCH
	var board_height = board.get("size", {}).get("height", 60) * PX_PER_INCH
	var dest_x = float(dest.get("x", 0))
	var dest_y = float(dest.get("y", 0))
	if dest_x < 0 or dest_x > board_width or dest_y < 0 or dest_y > board_height:
		return {"valid": false, "errors": ["Destination is off the board"]}

	return {"valid": true, "errors": []}

func _validate_confirm_scout_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	if active_scout_move.is_empty() or active_scout_move.get("unit_id", "") != unit_id:
		return {"valid": false, "errors": ["No active scout move for unit: " + unit_id]}

	var model_positions = action.get("model_positions", [])
	if model_positions.is_empty():
		return {"valid": false, "errors": ["Missing model_positions"]}

	return {"valid": true, "errors": []}

func _validate_skip_scout_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing unit_id"]}

	if scouted_units.has(unit_id):
		return {"valid": false, "errors": ["Unit already scouted"]}

	return {"valid": true, "errors": []}

func _validate_end_scout_moves(action: Dictionary) -> Dictionary:
	if not active_scout_move.is_empty():
		return {"valid": false, "errors": ["Cannot end scout moves while a move is in progress"]}
	return {"valid": true, "errors": []}

# ============================================================================
# PROCESSING
# ============================================================================

func _process_begin_scout_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var unit = get_unit(unit_id)
	var max_inches = GameState.get_scout_range(unit_id)

	# Store original positions for range validation
	var original_positions = []
	for model in unit.get("models", []):
		var pos = model.get("position", null)
		if pos != null:
			original_positions.append({"x": pos.get("x", pos.x if pos is Vector2 else 0), "y": pos.get("y", pos.y if pos is Vector2 else 0)})
		else:
			original_positions.append(null)

	active_scout_move = {
		"unit_id": unit_id,
		"max_inches": max_inches,
		"original_positions": original_positions
	}

	var unit_name = unit.get("meta", {}).get("name", "Unknown")
	log_phase_message("Scout move begun for %s (max %d\")" % [unit_name, int(max_inches)])
	emit_signal("scout_move_begun", unit_id, max_inches)

	return create_result(true, [], "")

func _process_set_scout_model_dest(action: Dictionary) -> Dictionary:
	# This action is validated but doesn't create state changes yet
	# The actual positions are set when CONFIRM_SCOUT_MOVE fires
	# This is used for client-side preview/validation
	return create_result(true, [], "")

func _process_confirm_scout_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var model_positions = action.get("model_positions", [])
	var changes = []

	# Update each model's position
	for i in range(model_positions.size()):
		var pos = model_positions[i]
		if pos != null:
			var x = float(pos.get("x", pos.x if pos is Vector2 else 0))
			var y = float(pos.get("y", pos.y if pos is Vector2 else 0))
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [unit_id, i],
				"value": {"x": x, "y": y}
			})

	# Mark unit as having scouted (set a flag)
	changes.append({
		"op": "set",
		"path": "units.%s.flags.scouted" % unit_id,
		"value": true
	})

	scouted_units[unit_id] = true

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", "Unknown")
	log_phase_message("Scout move confirmed for %s" % unit_name)
	emit_signal("scout_move_confirmed", unit_id)

	# Clear active move
	active_scout_move.clear()

	# Check if this player is done scouting
	_check_player_scout_completion()

	return create_result(true, changes, "")

func _process_skip_scout_unit(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	scouted_units[unit_id] = true

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", "Unknown")
	log_phase_message("Scout move skipped for %s" % unit_name)

	# Clear active move if this unit was being moved
	if active_scout_move.get("unit_id", "") == unit_id:
		active_scout_move.clear()

	_check_player_scout_completion()

	return create_result(true, [], "")

func _process_end_scout_moves(action: Dictionary) -> Dictionary:
	# Mark all remaining scout units for this player as skipped
	var player = get_current_player()
	var scout_units = GameState.get_scout_units_for_player(player)
	for unit_id in scout_units:
		if not scouted_units.has(unit_id):
			scouted_units[unit_id] = true

	_advance_to_next_scout_player()

	return create_result(true, [], "")

# ============================================================================
# PHASE FLOW
# ============================================================================

func _check_player_scout_completion() -> void:
	"""Check if the current player has finished all their scout moves"""
	var player = get_current_player()
	var scout_units = GameState.get_scout_units_for_player(player)

	var all_done = true
	for unit_id in scout_units:
		if not scouted_units.has(unit_id):
			all_done = false
			break

	if all_done:
		emit_signal("scout_phase_player_done", player)
		_advance_to_next_scout_player()

func _advance_to_next_scout_player() -> void:
	"""Move to the next player's scout moves, or complete the phase"""
	var current_idx = scout_player_order.find(current_scout_player)

	if current_idx < scout_player_order.size() - 1:
		# Move to next player
		var next_player = scout_player_order[current_idx + 1]
		var next_scouts = GameState.get_scout_units_for_player(next_player)

		if next_scouts.is_empty():
			# Next player has no scouts, phase is done
			log_phase_message("No scout units for Player %d - completing Scout Moves phase" % next_player)
			phase_done = true
			emit_signal("phase_completed")
		else:
			# Check if all next player's scouts are already done
			var all_done = true
			for unit_id in next_scouts:
				if not scouted_units.has(unit_id):
					all_done = false
					break

			if all_done:
				log_phase_message("All scouts done for Player %d - completing Scout Moves phase" % next_player)
				phase_done = true
				emit_signal("phase_completed")
			else:
				current_scout_player = next_player
				GameState.set_active_player(next_player)
				log_phase_message("Switching to Player %d for scout moves" % next_player)
	else:
		# All players done
		log_phase_message("All scout moves complete - phase done")
		phase_done = true
		emit_signal("phase_completed")

func _should_complete_phase() -> bool:
	return phase_done
