extends BasePhase
class_name ScoutPhase

const BasePhase = preload("res://phases/BasePhase.gd")

# ScoutPhase - Handles the pre-game Scout moves between Deployment and Turn 1
# Per 10e rules:
# - Units with Scout X" can make a Normal Move of up to X" after deployment
# - Must end >9" from all enemy models
# - Player going first moves their Scout units first
# - Dedicated Transports inherit Scout if all embarked units have it

const SCOUT_MIN_ENEMY_DISTANCE_INCHES: float = 9.0
const PX_PER_INCH: float = 40.0

# Track which units have completed their Scout move
var scout_units_pending: Dictionary = {}  # player -> [unit_ids]
var scout_units_completed: Array = []
var current_scout_player: int = 1  # Player going first moves Scouts first
var active_scout_moves: Dictionary = {}  # unit_id -> move_data (mirrors MovementPhase pattern)

func _init():
	phase_type = GameStateData.Phase.SCOUT

func _on_phase_enter() -> void:
	log_phase_message("Entering Scout Phase")
	scout_units_pending.clear()
	scout_units_completed.clear()
	active_scout_moves.clear()

	# Determine which player goes first (player 1 by default, going-first player moves scouts first)
	current_scout_player = get_current_player()

	# Find all units with Scout ability for each player
	var p1_scouts = GameState.get_scout_units_for_player(1)
	var p2_scouts = GameState.get_scout_units_for_player(2)

	scout_units_pending[1] = p1_scouts
	scout_units_pending[2] = p2_scouts

	log_phase_message("Player 1 Scout units: %s" % str(p1_scouts))
	log_phase_message("Player 2 Scout units: %s" % str(p2_scouts))

	var total_scouts = p1_scouts.size() + p2_scouts.size()

	if total_scouts == 0:
		log_phase_message("No units with Scout ability found, skipping Scout phase")
		# Use call_deferred to avoid emitting signal during enter_phase
		call_deferred("_complete_phase")
		return

	# Set active player to the first player (who goes first moves scouts first)
	log_phase_message("Scout phase active - Player %d moves first" % current_scout_player)

	# If the current first player has no scouts, switch to the other player
	if scout_units_pending.get(current_scout_player, []).size() == 0:
		current_scout_player = 3 - current_scout_player
		GameState.set_active_player(current_scout_player)
		log_phase_message("First player has no scouts, switching to Player %d" % current_scout_player)

func _complete_phase() -> void:
	emit_signal("phase_completed")

func _on_phase_exit() -> void:
	log_phase_message("Exiting Scout Phase")
	active_scout_moves.clear()

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
		"SKIP_SCOUT_MOVE":
			return _validate_skip_scout_move(action)
		"END_SCOUT_PHASE":
			return _validate_end_scout_phase(action)
		"DEBUG_MOVE":
			return {"valid": true}
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	match action_type:
		"BEGIN_SCOUT_MOVE":
			return _process_begin_scout_move(action)
		"SET_SCOUT_MODEL_DEST":
			return _process_set_scout_model_dest(action)
		"CONFIRM_SCOUT_MOVE":
			return _process_confirm_scout_move(action)
		"SKIP_SCOUT_MOVE":
			return _process_skip_scout_move(action)
		"END_SCOUT_PHASE":
			return _process_end_scout_phase(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

# ========================================
# Validation Methods
# ========================================

func _validate_begin_scout_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}

	# Must belong to active player
	var active_player = get_current_player()
	if unit.get("owner", 0) != active_player:
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Must have Scout ability
	if not GameState.unit_has_scout(unit_id):
		return {"valid": false, "errors": ["Unit does not have Scout ability: " + unit_id]}

	# Must be deployed (not in reserves)
	if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
		return {"valid": false, "errors": ["Unit must be deployed to make a Scout move"]}

	# Must not have already completed scout move
	if unit_id in scout_units_completed:
		return {"valid": false, "errors": ["Unit has already completed its Scout move"]}

	# Must be in the pending list
	var pending = scout_units_pending.get(active_player, [])
	if unit_id not in pending:
		return {"valid": false, "errors": ["Unit is not eligible for Scout move"]}

	# Must not already have an active scout move in progress
	if active_scout_moves.has(unit_id):
		return {"valid": false, "errors": ["Unit already has a Scout move in progress"]}

	return {"valid": true, "errors": []}

func _validate_set_scout_model_dest(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var model_id = action.get("model_id", "")
	var dest = action.get("destination", null)

	if unit_id == "" or model_id == "":
		return {"valid": false, "errors": ["Missing unit_id or model_id"]}

	if dest == null:
		return {"valid": false, "errors": ["Missing destination"]}

	# Must have an active scout move
	if not active_scout_moves.has(unit_id):
		return {"valid": false, "errors": ["No active Scout move for unit: " + unit_id]}

	var move_data = active_scout_moves[unit_id]
	var scout_distance = move_data.get("scout_distance", 6.0)

	# Get model's current position
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	var model_index = -1
	for i in range(models.size()):
		if models[i].get("id", "") == model_id:
			model_index = i
			break

	if model_index == -1:
		return {"valid": false, "errors": ["Model not found: " + model_id]}

	var model = models[model_index]
	var current_pos_dict = model.get("position", null)
	if current_pos_dict == null:
		return {"valid": false, "errors": ["Model has no position"]}

	var current_pos = Vector2(
		current_pos_dict.get("x", 0) if current_pos_dict is Dictionary else current_pos_dict.x,
		current_pos_dict.get("y", 0) if current_pos_dict is Dictionary else current_pos_dict.y
	)

	var dest_pos = Vector2(
		dest.get("x", dest.x if dest is Vector2 else 0),
		dest.get("y", dest.y if dest is Vector2 else 0)
	)

	# Check movement distance
	var distance_px = current_pos.distance_to(dest_pos)
	var distance_inches = distance_px / PX_PER_INCH
	if distance_inches > scout_distance + 0.02:  # Small tolerance for floating point
		return {"valid": false, "errors": ["Scout move exceeds max distance: %.1f\" > %d\"" % [distance_inches, scout_distance]]}

	# Check >9" from all enemy models (edge-to-edge)
	var model_base_mm = model.get("base_mm", 32)
	var model_radius_inches = (model_base_mm / 2.0) / 25.4
	var owner = unit.get("owner", 0)
	var enemy_positions = GameState.get_enemy_model_positions(owner)
	for enemy in enemy_positions:
		var enemy_pos_px = Vector2(enemy.x, enemy.y)
		var enemy_radius_inches = (enemy.base_mm / 2.0) / 25.4
		var dist_px = dest_pos.distance_to(enemy_pos_px)
		var dist_inches = dist_px / PX_PER_INCH
		var edge_dist = dist_inches - model_radius_inches - enemy_radius_inches
		if edge_dist < SCOUT_MIN_ENEMY_DISTANCE_INCHES:
			return {"valid": false, "errors": ["Scout move must end >9\" from enemy models (%.1f\")" % edge_dist]}

	# Check board bounds
	var board_width_px = GameState.state.board.size.width * PX_PER_INCH
	var board_height_px = GameState.state.board.size.height * PX_PER_INCH
	if dest_pos.x < 0 or dest_pos.x > board_width_px or dest_pos.y < 0 or dest_pos.y > board_height_px:
		return {"valid": false, "errors": ["Model must stay on the battlefield"]}

	# Check overlap with other models
	if _position_overlaps_other_models(dest_pos, model_base_mm, unit_id, model_id):
		return {"valid": false, "errors": ["Model cannot overlap with other models"]}

	return {"valid": true, "errors": []}

func _validate_confirm_scout_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing unit_id"]}

	if not active_scout_moves.has(unit_id):
		return {"valid": false, "errors": ["No active Scout move for unit: " + unit_id]}

	var move_data = active_scout_moves[unit_id]
	var staged_positions = move_data.get("staged_positions", {})

	# At least one model must have a staged position (or all at original = skip)
	# Actually, confirming with no moves is fine (unit stays in place)

	# Validate all staged positions pass the >9" enemy distance check
	var unit = get_unit(unit_id)
	var owner = unit.get("owner", 0)
	var model_base_mm = unit.get("models", [{}])[0].get("base_mm", 32)
	var model_radius_inches = (model_base_mm / 2.0) / 25.4

	for model_id in staged_positions:
		var pos = staged_positions[model_id]
		var dest_pos = Vector2(pos.x, pos.y) if pos is Dictionary else pos
		var enemy_positions = GameState.get_enemy_model_positions(owner)
		for enemy in enemy_positions:
			var enemy_pos_px = Vector2(enemy.x, enemy.y)
			var enemy_radius_inches = (enemy.base_mm / 2.0) / 25.4
			var dist_px = dest_pos.distance_to(enemy_pos_px)
			var dist_inches = dist_px / PX_PER_INCH
			var edge_dist = dist_inches - model_radius_inches - enemy_radius_inches
			if edge_dist < SCOUT_MIN_ENEMY_DISTANCE_INCHES:
				return {"valid": false, "errors": ["Model %s ends <9\" from enemy models (%.1f\")" % [model_id, edge_dist]]}

	return {"valid": true, "errors": []}

func _validate_skip_scout_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}

	# Must belong to active player
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Must be in pending list
	var pending = scout_units_pending.get(get_current_player(), [])
	if unit_id not in pending:
		return {"valid": false, "errors": ["Unit is not eligible for Scout move"]}

	return {"valid": true, "errors": []}

func _validate_end_scout_phase(action: Dictionary) -> Dictionary:
	# Can only end if no units remain pending for any player
	var total_pending = 0
	for player in scout_units_pending:
		total_pending += scout_units_pending[player].size()

	if total_pending > 0:
		return {"valid": false, "errors": ["Scout units still pending: %d" % total_pending]}

	return {"valid": true, "errors": []}

# ========================================
# Process Methods
# ========================================

func _process_begin_scout_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var scout_distance = GameState.get_scout_distance(unit_id)

	active_scout_moves[unit_id] = {
		"scout_distance": scout_distance,
		"staged_positions": {},  # model_id -> {x, y}
		"original_positions": {}  # model_id -> {x, y}
	}

	# Store original positions
	var unit = get_unit(unit_id)
	for model in unit.get("models", []):
		var pos = model.get("position", null)
		if pos != null:
			active_scout_moves[unit_id]["original_positions"][model.id] = {
				"x": pos.get("x", 0) if pos is Dictionary else pos.x,
				"y": pos.get("y", 0) if pos is Dictionary else pos.y
			}

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Begin Scout move for %s (Scout %d\")" % [unit_name, int(scout_distance)])

	return create_result(true, [])

func _process_set_scout_model_dest(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var model_id = action.get("model_id", "")
	var dest = action.get("destination", null)

	if not active_scout_moves.has(unit_id):
		return create_result(false, [], "No active Scout move for unit")

	# Store the staged position
	var dest_pos = {
		"x": dest.get("x", dest.x if dest is Vector2 else 0),
		"y": dest.get("y", dest.y if dest is Vector2 else 0)
	}
	active_scout_moves[unit_id]["staged_positions"][model_id] = dest_pos

	return create_result(true, [])

func _process_confirm_scout_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	if not active_scout_moves.has(unit_id):
		return create_result(false, [], "No active Scout move for unit")

	var move_data = active_scout_moves[unit_id]
	var staged_positions = move_data.get("staged_positions", {})
	var changes = []

	# Apply all staged model positions to game state
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])

	for i in range(models.size()):
		var model = models[i]
		var mid = model.get("id", "")
		if staged_positions.has(mid):
			var pos = staged_positions[mid]
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.position" % [unit_id, i],
				"value": {"x": pos.x, "y": pos.y}
			})

	# Apply changes through PhaseManager
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)

	# Update local snapshot
	_apply_changes_to_local_state(changes)

	# Mark unit as completed
	_mark_scout_complete(unit_id)

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var models_moved = staged_positions.size()
	log_phase_message("Scout move confirmed for %s (%d models moved)" % [unit_name, models_moved])

	# Clean up active move
	active_scout_moves.erase(unit_id)

	# Check if we need to switch players or complete
	_check_scout_progression()

	return create_result(true, changes)

func _process_skip_scout_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")

	# If there's an active move, clean it up
	if active_scout_moves.has(unit_id):
		active_scout_moves.erase(unit_id)

	# Mark unit as completed (skipped counts as completed)
	_mark_scout_complete(unit_id)

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Scout move skipped for %s" % unit_name)

	# Check if we need to switch players or complete
	_check_scout_progression()

	return create_result(true, [])

func _process_end_scout_phase(action: Dictionary) -> Dictionary:
	log_phase_message("Scout phase ending")
	emit_signal("phase_completed")
	return create_result(true, [])

# ========================================
# Helper Methods
# ========================================

func _mark_scout_complete(unit_id: String) -> void:
	scout_units_completed.append(unit_id)

	# Remove from pending lists
	for player in scout_units_pending:
		var pending = scout_units_pending[player]
		var idx = pending.find(unit_id)
		if idx >= 0:
			pending.remove_at(idx)

func _check_scout_progression() -> void:
	"""Check if all scouts for current player are done, and switch/complete accordingly."""
	var current_player = get_current_player()
	var current_pending = scout_units_pending.get(current_player, [])

	if current_pending.size() == 0:
		# Current player is done with scouts
		var other_player = 3 - current_player
		var other_pending = scout_units_pending.get(other_player, [])

		if other_pending.size() > 0:
			# Switch to other player for their scouts
			GameState.set_active_player(other_player)
			# Update local snapshot
			game_state_snapshot = GameState.create_snapshot()
			log_phase_message("Player %d scouts complete, switching to Player %d" % [current_player, other_player])
		else:
			# All scouts done, complete the phase
			log_phase_message("All Scout moves complete")
			emit_signal("phase_completed")

func _position_overlaps_other_models(pos: Vector2, base_mm: int, skip_unit_id: String, skip_model_id: String) -> bool:
	"""Check if a position overlaps with any deployed model."""
	var model_radius_px = (base_mm / 2.0) / 25.4 * PX_PER_INCH
	var units = game_state_snapshot.get("units", {})

	for unit_id in units:
		var unit = units[unit_id]
		var status = unit.get("status", 0)
		if status != GameStateData.UnitStatus.DEPLOYED and status != GameStateData.UnitStatus.MOVED:
			continue

		var models = unit.get("models", [])
		for model in models:
			if not model.get("alive", true):
				continue
			# Skip the model being moved
			if unit_id == skip_unit_id and model.get("id", "") == skip_model_id:
				continue

			var model_pos_dict = model.get("position", null)
			if model_pos_dict == null:
				continue

			var model_pos = Vector2(
				model_pos_dict.get("x", 0) if model_pos_dict is Dictionary else model_pos_dict.x,
				model_pos_dict.get("y", 0) if model_pos_dict is Dictionary else model_pos_dict.y
			)
			var other_radius_px = (model.get("base_mm", 32) / 2.0) / 25.4 * PX_PER_INCH
			var distance = pos.distance_to(model_pos)
			if distance < (model_radius_px + other_radius_px):
				return true

	return false

func _apply_changes_to_local_state(changes: Array) -> void:
	for change in changes:
		_apply_single_change_to_local(change)
	# Also refresh from GameState to stay in sync
	game_state_snapshot = GameState.create_snapshot()

func _apply_single_change_to_local(change: Dictionary) -> void:
	match change.get("op", ""):
		"set":
			_set_local_value(change.path, change.value)

func _set_local_value(path: String, value) -> void:
	var parts = path.split(".")
	var current = game_state_snapshot

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

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()
	var pending = scout_units_pending.get(current_player, [])

	for unit_id in pending:
		var unit = get_unit(unit_id)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var scout_dist = GameState.get_scout_distance(unit_id)

		# Can begin a scout move
		if not active_scout_moves.has(unit_id):
			actions.append({
				"type": "BEGIN_SCOUT_MOVE",
				"unit_id": unit_id,
				"description": "Scout move %s (%d\")" % [unit_name, int(scout_dist)]
			})

		# Can skip the scout move
		actions.append({
			"type": "SKIP_SCOUT_MOVE",
			"unit_id": unit_id,
			"description": "Skip Scout move for %s" % unit_name
		})

	# If there are active moves, offer confirm
	for unit_id in active_scout_moves:
		var unit = get_unit(unit_id)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		actions.append({
			"type": "CONFIRM_SCOUT_MOVE",
			"unit_id": unit_id,
			"description": "Confirm Scout move for %s" % unit_name
		})

	# If all pending are done, offer end phase
	var total_pending = 0
	for player in scout_units_pending:
		total_pending += scout_units_pending[player].size()

	if total_pending == 0 and active_scout_moves.size() == 0:
		actions.append({
			"type": "END_SCOUT_PHASE",
			"description": "End Scout Phase"
		})

	return actions

func _should_complete_phase() -> bool:
	var total_pending = 0
	for player in scout_units_pending:
		total_pending += scout_units_pending[player].size()
	return total_pending == 0 and active_scout_moves.size() == 0
