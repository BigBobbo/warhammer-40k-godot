extends BasePhase
class_name MovementPhase

# MovementPhase - Full implementation of the Movement phase following 10e rules
# Supports: Normal Move, Advance, Fall Back, Remain Stationary

signal unit_move_begun(unit_id: String, mode: String)
signal model_drop_preview(unit_id: String, model_id: String, path_px: Array, inches_used: float, legal: bool)
signal model_drop_committed(unit_id: String, model_id: String, dest_px: Vector2)
signal unit_move_confirmed(unit_id: String, result_summary: Dictionary)
signal unit_move_reset(unit_id: String)

const ENGAGEMENT_RANGE_INCHES: float = 1.0  # 10e standard ER

# Movement state tracking
var active_moves: Dictionary = {}  # unit_id -> move_data
var dice_log: Array = []

func _init():
	phase_type = GameStateData.Phase.MOVEMENT

func _on_phase_enter() -> void:
	log_phase_message("Entering Movement Phase")
	active_moves.clear()
	dice_log.clear()
	
	# Movement phase should always start with Player 1
	# (In a full game, this would alternate based on who has initiative)
	if GameState.get_active_player() != 1:
		log_phase_message("Setting active player to 1 for movement phase")
		GameState.set_active_player(1)
	
	_initialize_movement()

func _on_phase_exit() -> void:
	log_phase_message("Exiting Movement Phase")
	# Clear any temporary movement data
	for unit_id in active_moves:
		_clear_unit_move_state(unit_id)

func _initialize_movement() -> void:
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	var can_move = false
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) == GameStateData.UnitStatus.DEPLOYED:
			can_move = true
			break
	
	if not can_move:
		log_phase_message("No units available for movement, completing phase")
		emit_signal("phase_completed")

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"BEGIN_NORMAL_MOVE":
			return _validate_begin_normal_move(action)
		"BEGIN_ADVANCE":
			return _validate_begin_advance(action)
		"BEGIN_FALL_BACK":
			return _validate_begin_fall_back(action)
		"SET_MODEL_DEST":
			return _validate_set_model_dest(action)
		"UNDO_LAST_MODEL_MOVE":
			return _validate_undo_last_model_move(action)
		"RESET_UNIT_MOVE":
			return _validate_reset_unit_move(action)
		"CONFIRM_UNIT_MOVE":
			return _validate_confirm_unit_move(action)
		"REMAIN_STATIONARY":
			return _validate_remain_stationary(action)
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")
	
	match action_type:
		"BEGIN_NORMAL_MOVE":
			return _process_begin_normal_move(action)
		"BEGIN_ADVANCE":
			return _process_begin_advance(action)
		"BEGIN_FALL_BACK":
			return _process_begin_fall_back(action)
		"SET_MODEL_DEST":
			return _process_set_model_dest(action)
		"UNDO_LAST_MODEL_MOVE":
			return _process_undo_last_model_move(action)
		"RESET_UNIT_MOVE":
			return _process_reset_unit_move(action)
		"CONFIRM_UNIT_MOVE":
			return _process_confirm_unit_move(action)
		"REMAIN_STATIONARY":
			return _process_remain_stationary(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

# Validation Methods

func _validate_begin_normal_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}
	
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}
	
	if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
		return {"valid": false, "errors": ["Unit is not deployed"]}
	
	# Check if unit has already moved
	if unit.get("flags", {}).get("moved", false):
		return {"valid": false, "errors": ["Unit has already moved this phase"]}
	
	# Check if unit is in engagement range (cannot use Normal Move if engaged)
	if _is_unit_engaged(unit_id):
		return {"valid": false, "errors": ["Unit is engaged, must Fall Back instead"]}
	
	return {"valid": true, "errors": []}

func _validate_begin_advance(action: Dictionary) -> Dictionary:
	# Same validation as normal move, plus advance-specific checks
	var base_validation = _validate_begin_normal_move(action)
	if not base_validation.valid:
		return base_validation
	
	# No additional restrictions for advance at this stage
	return {"valid": true, "errors": []}

func _validate_begin_fall_back(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}
	
	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}
	
	if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
		return {"valid": false, "errors": ["Unit is not deployed"]}
	
	# Check if unit has already moved
	if unit.get("flags", {}).get("moved", false):
		return {"valid": false, "errors": ["Unit has already moved this phase"]}
	
	# Fall Back is only allowed if engaged
	if not _is_unit_engaged(unit_id):
		return {"valid": false, "errors": ["Unit is not engaged, use Normal Move instead"]}
	
	return {"valid": true, "errors": []}

func _validate_set_model_dest(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var model_id = payload.get("model_id", "")
	var dest = payload.get("dest", [])
	
	if unit_id == "" or model_id == "" or dest.size() != 2:
		return {"valid": false, "errors": ["Missing required fields"]}
	
	# Check if unit has an active move
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["No active move for unit"]}
	
	var move_data = active_moves[unit_id]
	var dest_vec = Vector2(dest[0], dest[1])
	
	# Validate movement distance
	var model = _get_model_in_unit(unit_id, model_id)
	if model.is_empty():
		return {"valid": false, "errors": ["Model not found in unit"]}
	
	var current_pos = _get_model_position(model)
	if current_pos == null:
		return {"valid": false, "errors": ["Model has no current position"]}
	
	var distance_inches = Measurement.distance_inches(current_pos, dest_vec)
	if distance_inches > move_data.move_cap_inches:
		return {"valid": false, "errors": ["Move exceeds cap: %.1f\" > %.1f\"" % [distance_inches, move_data.move_cap_inches]]}
	
	# Check engagement range restrictions
	var er_check = _check_engagement_range_at_position(unit_id, model_id, dest_vec, move_data.mode)
	if not er_check.valid:
		return {"valid": false, "errors": er_check.errors}
	
	# Check terrain collision
	if _position_intersects_terrain(dest_vec, model.get("base_mm", 32)):
		return {"valid": false, "errors": ["Position intersects impassable terrain"]}
	
	return {"valid": true, "errors": []}

func _validate_undo_last_model_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["No active move for unit"]}
	
	var move_data = active_moves[unit_id]
	if move_data.model_moves.is_empty():
		return {"valid": false, "errors": ["No model moves to undo"]}
	
	return {"valid": true, "errors": []}

func _validate_reset_unit_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["No active move for unit"]}
	
	return {"valid": true, "errors": []}

func _validate_confirm_unit_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	if not active_moves.has(unit_id):
		return {"valid": false, "errors": ["No active move for unit"]}
	
	var move_data = active_moves[unit_id]
	
	# For Fall Back, ensure all models end outside engagement range
	if move_data.mode == "FALL_BACK":
		for model_move in move_data.model_moves:
			var dest = model_move.dest
			if _is_position_in_engagement_range(unit_id, model_move.model_id, dest):
				return {"valid": false, "errors": ["Model %s would still be in engagement range" % model_move.model_id]}
	
	return {"valid": true, "errors": []}

func _validate_remain_stationary(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing actor_unit_id"]}
	
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found"]}
	
	if unit.get("flags", {}).get("moved", false):
		return {"valid": false, "errors": ["Unit has already acted this phase"]}
	
	return {"valid": true, "errors": []}

# Processing Methods

func _process_begin_normal_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)
	var move_inches = unit.get("meta", {}).get("stats", {}).get("move", 6)
	
	active_moves[unit_id] = {
		"mode": "NORMAL",
		"move_cap_inches": move_inches,
		"model_moves": [],
		"dice_rolls": []
	}
	
	emit_signal("unit_move_begun", unit_id, "NORMAL")
	log_phase_message("Beginning normal move for %s (M: %d\")" % [unit.get("meta", {}).get("name", unit_id), move_inches])
	
	return create_result(true, [
		{
			"op": "set",
			"path": "units.%s.flags.move_cap_inches" % unit_id,
			"value": move_inches
		}
	])

func _process_begin_advance(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)
	var move_inches = unit.get("meta", {}).get("stats", {}).get("move", 6)
	
	# Roll D6 for advance
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var advance_roll = rng.randi_range(1, 6)
	var total_move = move_inches + advance_roll
	
	active_moves[unit_id] = {
		"mode": "ADVANCE",
		"move_cap_inches": total_move,
		"model_moves": [],
		"dice_rolls": [{"context": "advance", "rolls": [advance_roll]}]
	}
	
	dice_log.append({
		"unit_id": unit_id,
		"unit_name": unit.get("meta", {}).get("name", unit_id),
		"type": "Advance",
		"roll": advance_roll,
		"result": "Move cap = %d\" (M %d\" + %d\")" % [total_move, move_inches, advance_roll]
	})
	
	emit_signal("unit_move_begun", unit_id, "ADVANCE")
	log_phase_message("Advance: %s → D6 = %d → Move cap = %d\"" % [unit.get("meta", {}).get("name", unit_id), advance_roll, total_move])
	
	return create_result(true, [
		{
			"op": "set",
			"path": "units.%s.flags.advanced" % unit_id,
			"value": true
		},
		{
			"op": "set",
			"path": "units.%s.flags.move_cap_inches" % unit_id,
			"value": total_move
		}
	], "", {"dice": [{"context": "advance", "n": 1, "rolls": [advance_roll]}]})

func _process_begin_fall_back(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)
	var move_inches = unit.get("meta", {}).get("stats", {}).get("move", 6)
	
	active_moves[unit_id] = {
		"mode": "FALL_BACK",
		"move_cap_inches": move_inches,
		"model_moves": [],
		"dice_rolls": [],
		"battle_shocked": unit.get("status_effects", {}).get("battle_shocked", false)
	}
	
	emit_signal("unit_move_begun", unit_id, "FALL_BACK")
	log_phase_message("Beginning fall back for %s (M: %d\")" % [unit.get("meta", {}).get("name", unit_id), move_inches])
	
	return create_result(true, [
		{
			"op": "set",
			"path": "units.%s.flags.fell_back" % unit_id,
			"value": true
		},
		{
			"op": "set",
			"path": "units.%s.flags.move_cap_inches" % unit_id,
			"value": move_inches
		}
	])

func _process_set_model_dest(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var payload = action.get("payload", {})
	var model_id = payload.get("model_id", "")
	var dest = payload.get("dest", [])
	var dest_vec = Vector2(dest[0], dest[1])
	
	var move_data = active_moves[unit_id]
	var model = _get_model_in_unit(unit_id, model_id)
	var current_pos = _get_model_position(model)
	
	# Calculate path and check for enemy crossing (Fall Back)
	var crosses_enemy = false
	if move_data.mode == "FALL_BACK":
		crosses_enemy = _path_crosses_enemy(current_pos, dest_vec, unit_id, model.get("base_mm", 32))
	
	# Add to model moves
	move_data.model_moves.append({
		"model_id": model_id,
		"from": current_pos,
		"dest": dest_vec,
		"crosses_enemy": crosses_enemy
	})
	
	var distance_inches = Measurement.distance_inches(current_pos, dest_vec)
	emit_signal("model_drop_committed", unit_id, model_id, dest_vec)
	
	return create_result(true, [
		{
			"op": "set",
			"path": "units.%s.models.%s.position" % [unit_id, _get_model_index(unit_id, model_id)],
			"value": {"x": dest_vec.x, "y": dest_vec.y}
		}
	])

func _process_undo_last_model_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var move_data = active_moves[unit_id]
	
	if move_data.model_moves.is_empty():
		return create_result(false, [], "No moves to undo")
	
	var last_move = move_data.model_moves.pop_back()
	var model_id = last_move.model_id
	var from_pos = last_move.from
	
	return create_result(true, [
		{
			"op": "set",
			"path": "units.%s.models.%s.position" % [unit_id, _get_model_index(unit_id, model_id)],
			"value": {"x": from_pos.x, "y": from_pos.y} if from_pos else null
		}
	])

func _process_reset_unit_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var move_data = active_moves[unit_id]
	var changes = []
	
	# Reset all model positions
	for model_move in move_data.model_moves:
		var from_pos = model_move.from
		changes.append({
			"op": "set",
			"path": "units.%s.models.%s.position" % [unit_id, _get_model_index(unit_id, model_move.model_id)],
			"value": {"x": from_pos.x, "y": from_pos.y} if from_pos else null
		})
	
	# Clear move data
	move_data.model_moves.clear()
	emit_signal("unit_move_reset", unit_id)
	
	return create_result(true, changes)

func _process_confirm_unit_move(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var move_data = active_moves[unit_id]
	var changes = []
	var additional_dice = []
	
	# Handle Desperate Escape for Fall Back
	if move_data.mode == "FALL_BACK":
		var desperate_escape_result = _process_desperate_escape(unit_id, move_data)
		changes.append_array(desperate_escape_result.changes)
		additional_dice.append_array(desperate_escape_result.dice)
	
	# Mark unit as moved
	changes.append({
		"op": "set",
		"path": "units.%s.flags.moved" % unit_id,
		"value": true
	})
	
	# Clear temporary move data
	changes.append({
		"op": "remove",
		"path": "units.%s.flags.move_cap_inches" % unit_id
	})
	
	# Set movement restrictions for later phases
	if move_data.mode == "ADVANCE":
		changes.append({
			"op": "set",
			"path": "units.%s.flags.cannot_shoot" % unit_id,
			"value": true
		})
		changes.append({
			"op": "set",
			"path": "units.%s.flags.cannot_charge" % unit_id,
			"value": true
		})
	elif move_data.mode == "FALL_BACK":
		changes.append({
			"op": "set",
			"path": "units.%s.flags.cannot_shoot" % unit_id,
			"value": true
		})
		changes.append({
			"op": "set",
			"path": "units.%s.flags.cannot_charge" % unit_id,
			"value": true
		})
	
	# Clean up active move
	active_moves.erase(unit_id)
	
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Confirmed %s move for %s" % [move_data.mode.to_lower(), unit_name])
	
	emit_signal("unit_move_confirmed", unit_id, {"mode": move_data.mode, "models_moved": move_data.model_moves.size()})
	
	return create_result(true, changes, "", {"dice": additional_dice})

func _process_remain_stationary(action: Dictionary) -> Dictionary:
	var unit_id = action.get("actor_unit_id", "")
	var unit = get_unit(unit_id)
	
	var changes = [
		{
			"op": "set",
			"path": "units.%s.flags.moved" % unit_id,
			"value": true
		},
		{
			"op": "set",
			"path": "units.%s.flags.remained_stationary" % unit_id,
			"value": true
		}
	]
	
	log_phase_message("%s remained stationary" % unit.get("meta", {}).get("name", unit_id))
	
	return create_result(true, changes)

func _process_desperate_escape(unit_id: String, move_data: Dictionary) -> Dictionary:
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	var changes = []
	var dice_rolls = []
	
	# Determine which models need Desperate Escape tests
	var models_to_test = []
	
	if move_data.battle_shocked:
		# All models test if Battle-shocked
		for i in range(models.size()):
			var model = models[i]
			if model.get("alive", true):
				models_to_test.append({"index": i, "id": model.get("id", "m%d" % i)})
	else:
		# Only models that crossed enemies
		for model_move in move_data.model_moves:
			if model_move.crosses_enemy:
				var idx = _get_model_index(unit_id, model_move.model_id)
				if idx >= 0:
					models_to_test.append({"index": idx, "id": model_move.model_id})
	
	if models_to_test.is_empty():
		return {"changes": [], "dice": []}
	
	# Roll D6 for each model
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var casualties = 0
	var rolls = []
	
	for model_data in models_to_test:
		var roll = rng.randi_range(1, 6)
		rolls.append(roll)
		if roll <= 2:
			casualties += 1
	
	# Apply casualties (player chooses which models)
	# For MVP, remove the first N alive models
	var removed = 0
	for i in range(models.size()):
		if removed >= casualties:
			break
		if models[i].get("alive", true):
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.alive" % [unit_id, i],
				"value": false
			})
			changes.append({
				"op": "set",
				"path": "units.%s.models.%d.current_wounds" % [unit_id, i],
				"value": 0
			})
			removed += 1
	
	dice_rolls.append({
		"context": "desperate_escape",
		"n": models_to_test.size(),
		"rolls": rolls
	})
	
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	if casualties > 0:
		dice_log.append({
			"unit_id": unit_id,
			"unit_name": unit_name,
			"type": "Desperate Escape",
			"rolls": rolls,
			"result": "%d models lost" % casualties
		})
		log_phase_message("Desperate Escape: %s → rolls: %s → models lost: %d" % [unit_name, str(rolls), casualties])
	
	return {"changes": changes, "dice": dice_rolls}

# Helper Methods

func _is_unit_engaged(unit_id: String) -> bool:
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	
	for model in models:
		if not model.get("alive", true):
			continue
		var pos = _get_model_position(model)
		if pos and _is_position_in_engagement_range(unit_id, model.get("id", ""), pos):
			return true
	
	return false

func _is_position_in_engagement_range(unit_id: String, model_id: String, pos: Vector2) -> bool:
	var er_px = Measurement.inches_to_px(ENGAGEMENT_RANGE_INCHES)
	var model = _get_model_in_unit(unit_id, model_id)
	var model_radius = Measurement.base_radius_px(model.get("base_mm", 32))
	
	# Check against all enemy units
	var current_player = get_current_player()
	var units = game_state_snapshot.get("units", {})
	
	for enemy_unit_id in units:
		var enemy_unit = units[enemy_unit_id]
		if enemy_unit.get("owner", 0) == current_player:
			continue  # Skip friendly units
		
		var enemy_models = enemy_unit.get("models", [])
		for enemy_model in enemy_models:
			if not enemy_model.get("alive", true):
				continue
			var enemy_pos = _get_model_position(enemy_model)
			if enemy_pos:
				var enemy_radius = Measurement.base_radius_px(enemy_model.get("base_mm", 32))
				var edge_distance = pos.distance_to(enemy_pos) - model_radius - enemy_radius
				if edge_distance <= er_px:
					return true
	
	return false

func _check_engagement_range_at_position(unit_id: String, model_id: String, dest: Vector2, mode: String) -> Dictionary:
	if mode == "FALL_BACK":
		# Fall Back allows ending outside ER even if path goes through
		if _is_position_in_engagement_range(unit_id, model_id, dest):
			return {"valid": false, "errors": ["Fall Back must end outside engagement range"]}
	else:
		# Normal and Advance cannot enter or end in ER
		if _is_position_in_engagement_range(unit_id, model_id, dest):
			return {"valid": false, "errors": ["Cannot end within engagement range"]}
	
	return {"valid": true, "errors": []}

func _path_crosses_enemy(from: Vector2, to: Vector2, unit_id: String, base_mm: int) -> bool:
	var model_radius = Measurement.base_radius_px(base_mm)
	var er_px = Measurement.inches_to_px(ENGAGEMENT_RANGE_INCHES)
	
	# Check if path segment crosses any enemy model bases
	var current_player = get_current_player()
	var units = game_state_snapshot.get("units", {})
	
	for enemy_unit_id in units:
		var enemy_unit = units[enemy_unit_id]
		if enemy_unit.get("owner", 0) == current_player:
			continue
		
		var enemy_models = enemy_unit.get("models", [])
		for enemy_model in enemy_models:
			if not enemy_model.get("alive", true):
				continue
			var enemy_pos = _get_model_position(enemy_model)
			if enemy_pos:
				var enemy_radius = Measurement.base_radius_px(enemy_model.get("base_mm", 32))
				# Check if line segment intersects circle
				if _segment_intersects_circle(from, to, enemy_pos, enemy_radius + model_radius + er_px):
					return true
	
	return false

func _segment_intersects_circle(seg_start: Vector2, seg_end: Vector2, circle_center: Vector2, radius: float) -> bool:
	# Calculate closest point on segment to circle center
	var seg_vec = seg_end - seg_start
	var to_center = circle_center - seg_start
	var t = clamp(to_center.dot(seg_vec) / seg_vec.length_squared(), 0.0, 1.0)
	var closest_point = seg_start + seg_vec * t
	var distance = closest_point.distance_to(circle_center)
	return distance <= radius

func _position_intersects_terrain(pos: Vector2, base_mm: int) -> bool:
	# MVP: Check against terrain polygons
	var terrain = game_state_snapshot.get("board", {}).get("terrain", [])
	var model_radius = Measurement.base_radius_px(base_mm)
	
	for terrain_piece in terrain:
		if terrain_piece.get("type", "") == "impassable":
			var poly = terrain_piece.get("poly", [])
			if _point_in_expanded_polygon(pos, poly, model_radius):
				return true
	
	return false

func _point_in_expanded_polygon(point: Vector2, poly: Array, expansion: float) -> bool:
	# Simple point-in-polygon test with expansion
	# For MVP, treat as rectangle bounds check
	if poly.is_empty():
		return false
	
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	
	for vertex in poly:
		min_x = min(min_x, vertex.x)
		max_x = max(max_x, vertex.x)
		min_y = min(min_y, vertex.y)
		max_y = max(max_y, vertex.y)
	
	return point.x >= (min_x - expansion) and point.x <= (max_x + expansion) and \
		   point.y >= (min_y - expansion) and point.y <= (max_y + expansion)

func _get_model_in_unit(unit_id: String, model_id: String) -> Dictionary:
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	for model in models:
		if model.get("id", "") == model_id:
			return model
	return {}

func _get_model_index(unit_id: String, model_id: String) -> int:
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	for i in range(models.size()):
		if models[i].get("id", "") == model_id:
			return i
	return -1

func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

func _clear_unit_move_state(unit_id: String) -> void:
	if active_moves.has(unit_id):
		active_moves.erase(unit_id)

func get_available_actions() -> Array:
	var actions = []
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
			continue
		
		# Skip if already moved
		if unit.get("flags", {}).get("moved", false):
			continue
		
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var is_engaged = _is_unit_engaged(unit_id)
		
		if is_engaged:
			# Can only Fall Back or Remain Stationary when engaged
			actions.append({
				"type": "BEGIN_FALL_BACK",
				"actor_unit_id": unit_id,
				"description": "Fall Back with " + unit_name
			})
			actions.append({
				"type": "REMAIN_STATIONARY",
				"actor_unit_id": unit_id,
				"description": unit_name + " remains stationary"
			})
		else:
			# Normal movement options
			actions.append({
				"type": "BEGIN_NORMAL_MOVE",
				"actor_unit_id": unit_id,
				"description": "Move " + unit_name
			})
			actions.append({
				"type": "BEGIN_ADVANCE",
				"actor_unit_id": unit_id,
				"description": "Advance with " + unit_name
			})
			actions.append({
				"type": "REMAIN_STATIONARY",
				"actor_unit_id": unit_id,
				"description": unit_name + " remains stationary"
			})
	
	# Add active move actions
	for unit_id in active_moves:
		actions.append({
			"type": "CONFIRM_UNIT_MOVE",
			"actor_unit_id": unit_id,
			"description": "Confirm move"
		})
		actions.append({
			"type": "RESET_UNIT_MOVE",
			"actor_unit_id": unit_id,
			"description": "Reset move"
		})
		if not active_moves[unit_id].model_moves.is_empty():
			actions.append({
				"type": "UNDO_LAST_MODEL_MOVE",
				"actor_unit_id": unit_id,
				"description": "Undo last model"
			})
	
	return actions

func _should_complete_phase() -> bool:
	# Check if all units have moved or been marked as stationary
	var current_player = get_current_player()
	var units = get_units_for_player(current_player)
	
	for unit_id in units:
		var unit = units[unit_id]
		if unit.get("status", 0) == GameStateData.UnitStatus.DEPLOYED:
			if not unit.get("flags", {}).get("moved", false):
				return false
	
	return true

func get_dice_log() -> Array:
	return dice_log

# Override create_result to support additional data
func create_result(success: bool, changes: Array = [], error: String = "", additional_data: Dictionary = {}) -> Dictionary:
	var result = {
		"success": success,
		"phase": phase_type,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	if success:
		result["changes"] = changes
		for key in additional_data:
			result[key] = additional_data[key]
	else:
		result["error"] = error
	
	return result