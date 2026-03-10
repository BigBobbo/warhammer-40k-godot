extends BasePhase
class_name RedeploymentPhase

const BasePhase = preload("res://phases/BasePhase.gd")

# RedeploymentPhase - Handles pre-game redeployment between Deployment and Scout Moves
# Per Core Rules Updates:
# - Rules that allow players to redeploy certain units after both armies are deployed
#   (e.g. HURON BLACKHEART's Red Corsairs ability, Phantasm stratagem) are always
#   resolved after the Deploy Armies step and before the Determine First Turn step.
# - Players alternate resolving redeployment rules, starting with the Attacker.
# - When redeploying, normal deployment rules apply (including Infiltrators positioning).
# - Units are removed from the battlefield then set up again following standard setup rules.

const PX_PER_INCH: float = 40.0

# Track which units have completed their redeployment
var redeploy_units_pending: Dictionary = {}  # player -> [unit_ids]
var redeploy_units_completed: Array = []
var current_redeploy_player: int = 1  # Attacker goes first
var active_redeploy: Dictionary = {}  # unit_id -> redeploy_data (staged model positions)

func _init():
	phase_type = GameStateData.Phase.REDEPLOYMENT

func _on_phase_enter() -> void:
	log_phase_message("Entering Redeployment Phase")
	redeploy_units_pending.clear()
	redeploy_units_completed.clear()
	active_redeploy.clear()

	# Attacker (Player 1) resolves redeployment first
	current_redeploy_player = 1

	# Find all units with redeployment abilities for each player
	var p1_redeploy = GameState.get_redeploy_units_for_player(1)
	var p2_redeploy = GameState.get_redeploy_units_for_player(2)

	redeploy_units_pending[1] = p1_redeploy
	redeploy_units_pending[2] = p2_redeploy

	log_phase_message("Player 1 redeploy units: %s" % str(p1_redeploy))
	log_phase_message("Player 2 redeploy units: %s" % str(p2_redeploy))

	var total_redeploy = p1_redeploy.size() + p2_redeploy.size()

	if total_redeploy == 0:
		log_phase_message("No units with redeployment abilities found, skipping Redeployment phase")
		# Use call_deferred to avoid emitting signal during enter_phase
		call_deferred("_complete_phase")
		return

	# Set active player to attacker (Player 1)
	log_phase_message("Redeployment phase active - Player %d (Attacker) resolves first" % current_redeploy_player)

	# If attacker has no redeploy units, switch to defender
	if redeploy_units_pending.get(current_redeploy_player, []).size() == 0:
		current_redeploy_player = 3 - current_redeploy_player
		GameState.set_active_player(current_redeploy_player)
		log_phase_message("Attacker has no redeploy units, switching to Player %d" % current_redeploy_player)

func _complete_phase() -> void:
	emit_signal("phase_completed")

func _on_phase_exit() -> void:
	log_phase_message("Exiting Redeployment Phase")
	active_redeploy.clear()

func validate_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	# Check base phase validation first (handles DEBUG_MOVE)
	var base_validation = super.validate_action(action)
	if not base_validation.get("valid", true):
		return base_validation

	match action_type:
		"BEGIN_REDEPLOY":
			return _validate_begin_redeploy(action)
		"SET_REDEPLOY_MODEL_POS":
			return _validate_set_redeploy_model_pos(action)
		"CONFIRM_REDEPLOY":
			return _validate_confirm_redeploy(action)
		"SKIP_REDEPLOY":
			return _validate_skip_redeploy(action)
		"SEND_TO_STRATEGIC_RESERVES":
			return _validate_send_to_reserves(action)
		"END_REDEPLOYMENT_PHASE":
			return _validate_end_redeployment_phase(action)
		"DEBUG_MOVE":
			return {"valid": true}
		_:
			return {"valid": false, "errors": ["Unknown action type: " + action_type]}

func process_action(action: Dictionary) -> Dictionary:
	var action_type = action.get("type", "")

	match action_type:
		"BEGIN_REDEPLOY":
			return _process_begin_redeploy(action)
		"SET_REDEPLOY_MODEL_POS":
			return _process_set_redeploy_model_pos(action)
		"CONFIRM_REDEPLOY":
			return _process_confirm_redeploy(action)
		"SKIP_REDEPLOY":
			return _process_skip_redeploy(action)
		"SEND_TO_STRATEGIC_RESERVES":
			return _process_send_to_reserves(action)
		"END_REDEPLOYMENT_PHASE":
			return _process_end_redeployment_phase(action)
		_:
			return create_result(false, [], "Unknown action type: " + action_type)

# ========================================
# Validation Methods
# ========================================

func _validate_begin_redeploy(action: Dictionary) -> Dictionary:
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

	# Must have redeployment ability
	if not GameState.unit_has_redeploy(unit_id):
		return {"valid": false, "errors": ["Unit does not have a redeployment ability: " + unit_id]}

	# Must be deployed
	if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
		return {"valid": false, "errors": ["Unit must be deployed to redeploy"]}

	# Must not have already completed redeployment
	if unit_id in redeploy_units_completed:
		return {"valid": false, "errors": ["Unit has already completed its redeployment"]}

	# Must be in the pending list
	var pending = redeploy_units_pending.get(active_player, [])
	if unit_id not in pending:
		return {"valid": false, "errors": ["Unit is not eligible for redeployment"]}

	# Must not already have an active redeploy in progress
	if active_redeploy.has(unit_id):
		return {"valid": false, "errors": ["Unit already has a redeployment in progress"]}

	return {"valid": true, "errors": []}

func _validate_set_redeploy_model_pos(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var model_id = action.get("model_id", "")
	var dest = action.get("destination", null)

	if unit_id == "" or model_id == "":
		return {"valid": false, "errors": ["Missing unit_id or model_id"]}

	if dest == null:
		return {"valid": false, "errors": ["Missing destination"]}

	# Must have an active redeploy
	if not active_redeploy.has(unit_id):
		return {"valid": false, "errors": ["No active redeployment for unit: " + unit_id]}

	# Get model
	var unit = get_unit(unit_id)
	var models = unit.get("models", [])
	var model_found = false
	var model_base_mm = 32
	for model in models:
		if model.get("id", "") == model_id:
			model_found = true
			model_base_mm = model.get("base_mm", 32)
			break

	if not model_found:
		return {"valid": false, "errors": ["Model not found: " + model_id]}

	var dest_pos = Vector2(
		dest.get("x", dest.x if dest is Vector2 else 0),
		dest.get("y", dest.y if dest is Vector2 else 0)
	)

	# Check board bounds
	var board_width_px = GameState.state.board.size.width * PX_PER_INCH
	var board_height_px = GameState.state.board.size.height * PX_PER_INCH
	if dest_pos.x < 0 or dest_pos.x > board_width_px or dest_pos.y < 0 or dest_pos.y > board_height_px:
		return {"valid": false, "errors": ["Model must stay on the battlefield"]}

	# Check deployment zone validity (redeployment uses standard deployment rules)
	var owner = unit.get("owner", 0)
	var zone = GameState.get_deployment_zone_for_player(owner)
	if not zone.is_empty():
		# Allow Infiltrators to deploy outside their deployment zone
		var has_infiltrators = GameState.unit_has_infiltrators(unit_id)
		if not has_infiltrators:
			# Must be within own deployment zone
			if not _is_in_deployment_zone(dest_pos, zone):
				return {"valid": false, "errors": ["Model must be placed within own deployment zone"]}

	# Check overlap with other models (excluding the unit being redeployed)
	if _position_overlaps_other_models(dest_pos, model_base_mm, unit_id, model_id):
		return {"valid": false, "errors": ["Model cannot overlap with other models"]}

	return {"valid": true, "errors": []}

func _validate_confirm_redeploy(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing unit_id"]}

	if not active_redeploy.has(unit_id):
		return {"valid": false, "errors": ["No active redeployment for unit: " + unit_id]}

	var redeploy_data = active_redeploy[unit_id]
	var staged_positions = redeploy_data.get("staged_positions", {})

	# All models must have staged positions
	var unit = get_unit(unit_id)
	var alive_models = []
	for model in unit.get("models", []):
		if model.get("alive", true):
			alive_models.append(model.get("id", ""))

	for mid in alive_models:
		if not staged_positions.has(mid):
			return {"valid": false, "errors": ["All models must have positions before confirming redeployment. Missing: " + mid]}

	return {"valid": true, "errors": []}

func _validate_skip_redeploy(action: Dictionary) -> Dictionary:
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
	var pending = redeploy_units_pending.get(get_current_player(), [])
	if unit_id not in pending:
		return {"valid": false, "errors": ["Unit is not eligible for redeployment"]}

	return {"valid": true, "errors": []}

func _validate_end_redeployment_phase(action: Dictionary) -> Dictionary:
	# Can only end if no units remain pending for any player
	var total_pending = 0
	for player in redeploy_units_pending:
		total_pending += redeploy_units_pending[player].size()

	if total_pending > 0:
		return {"valid": false, "errors": ["Redeploy units still pending: %d" % total_pending]}

	return {"valid": true, "errors": []}

# ========================================
# Process Methods
# ========================================

func _process_begin_redeploy(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")

	active_redeploy[unit_id] = {
		"staged_positions": {},  # model_id -> {x, y}
		"original_positions": {}  # model_id -> {x, y}
	}

	# Store original positions (for undo / reference)
	var unit = get_unit(unit_id)
	for model in unit.get("models", []):
		var pos = model.get("position", null)
		if pos != null:
			active_redeploy[unit_id]["original_positions"][model.id] = {
				"x": pos.get("x", 0) if pos is Dictionary else pos.x,
				"y": pos.get("y", 0) if pos is Dictionary else pos.y
			}

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Begin redeployment for %s" % unit_name)

	return create_result(true, [])

func _process_set_redeploy_model_pos(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var model_id = action.get("model_id", "")
	var dest = action.get("destination", null)

	if not active_redeploy.has(unit_id):
		return create_result(false, [], "No active redeployment for unit")

	# Store the staged position
	var dest_pos = {
		"x": dest.get("x", dest.x if dest is Vector2 else 0),
		"y": dest.get("y", dest.y if dest is Vector2 else 0)
	}
	active_redeploy[unit_id]["staged_positions"][model_id] = dest_pos

	return create_result(true, [])

func _process_confirm_redeploy(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	if not active_redeploy.has(unit_id):
		return create_result(false, [], "No active redeployment for unit")

	var redeploy_data = active_redeploy[unit_id]
	var staged_positions = redeploy_data.get("staged_positions", {})
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
	_mark_redeploy_complete(unit_id)

	# OA-2: Track Razgit's Magik Map redeployment usage
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	var player = unit.get("owner", 0)
	if faction_mgr and faction_mgr.has_razgit_magik_map(player):
		# Check if this unit is a Razgit's eligible unit (not a normal redeploy unit)
		if not GameState.unit_has_redeploy(unit_id):
			faction_mgr.mark_razgit_redeploy_used(player)

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var models_moved = staged_positions.size()
	log_phase_message("Redeployment confirmed for %s (%d models repositioned)" % [unit_name, models_moved])

	# Clean up active redeploy
	active_redeploy.erase(unit_id)

	# Check if we need to switch players or complete
	_check_redeploy_progression()

	return create_result(true, changes)

func _process_skip_redeploy(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")

	# If there's an active redeploy, clean it up
	if active_redeploy.has(unit_id):
		active_redeploy.erase(unit_id)

	# Mark unit as completed (skipped counts as completed)
	_mark_redeploy_complete(unit_id)

	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	log_phase_message("Redeployment skipped for %s (unit stays in place)" % unit_name)

	# Check if we need to switch players or complete
	_check_redeploy_progression()

	return create_result(true, [])

func _process_end_redeployment_phase(action: Dictionary) -> Dictionary:
	log_phase_message("Redeployment phase ending")
	emit_signal("phase_completed")
	return create_result(true, [])

# ---- OA-2: Razgit's Magik Map — Send to Strategic Reserves ----

func _validate_send_to_reserves(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	if unit_id == "":
		return {"valid": false, "errors": ["Missing unit_id"]}

	var unit = get_unit(unit_id)
	if unit.is_empty():
		return {"valid": false, "errors": ["Unit not found: " + unit_id]}

	if unit.get("owner", 0) != get_current_player():
		return {"valid": false, "errors": ["Unit does not belong to active player"]}

	# Must be in pending list
	var pending = redeploy_units_pending.get(get_current_player(), [])
	if unit_id not in pending:
		return {"valid": false, "errors": ["Unit is not eligible for redeployment"]}

	# Must be a Razgit's Magik Map unit (not a normal redeploy unit)
	if GameState.unit_has_redeploy(unit_id):
		return {"valid": false, "errors": ["Only Razgit's Magik Map units can be sent to Strategic Reserves"]}

	# Check Razgit's remaining slots
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if not faction_mgr or not faction_mgr.is_razgit_redeploy_available(get_current_player()):
		return {"valid": false, "errors": ["No Razgit's Magik Map redeployment slots remaining"]}

	return {"valid": true, "errors": []}

func _process_send_to_reserves(action: Dictionary) -> Dictionary:
	var unit_id = action.get("unit_id", "")
	var unit = get_unit(unit_id)
	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var player = unit.get("owner", 0)

	# Set unit status to STRATEGIC_RESERVES and clear model positions
	var changes = []
	changes.append({
		"op": "set",
		"path": "units.%s.status" % unit_id,
		"value": GameStateData.UnitStatus.UNDEPLOYED
	})

	# Clear model positions
	var models = unit.get("models", [])
	for i in range(models.size()):
		changes.append({
			"op": "set",
			"path": "units.%s.models.%d.position" % [unit_id, i],
			"value": null
		})

	# Apply changes
	if get_parent() and get_parent().has_method("apply_state_changes"):
		get_parent().apply_state_changes(changes)
	_apply_changes_to_local_state(changes)

	# Mark Razgit's redeploy as used
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	if faction_mgr:
		faction_mgr.mark_razgit_redeploy_used(player)

	# Mark unit as completed
	_mark_redeploy_complete(unit_id)

	log_phase_message("RAZGIT'S MAGIK MAP: %s sent to Strategic Reserves" % unit_name)

	# Check progression
	_check_redeploy_progression()

	return create_result(true, changes)

# ========================================
# Helper Methods
# ========================================

func _mark_redeploy_complete(unit_id: String) -> void:
	redeploy_units_completed.append(unit_id)

	# Remove from pending lists
	for player in redeploy_units_pending:
		var pending = redeploy_units_pending[player]
		var idx = pending.find(unit_id)
		if idx >= 0:
			pending.remove_at(idx)

func _check_redeploy_progression() -> void:
	"""Check if all redeploy for current player is done, and switch/complete accordingly.
	Phase completion is handled by BasePhase via _should_complete_phase()."""
	var current_player = get_current_player()
	var current_pending = redeploy_units_pending.get(current_player, [])

	if current_pending.size() == 0:
		# Current player is done with redeployment
		var other_player = 3 - current_player
		var other_pending = redeploy_units_pending.get(other_player, [])

		if other_pending.size() > 0:
			# Switch to other player for their redeployment
			GameState.set_active_player(other_player)
			# Update local snapshot
			game_state_snapshot = GameState.create_snapshot()
			log_phase_message("Player %d redeployment complete, switching to Player %d" % [current_player, other_player])
		else:
			# All redeployment done — BasePhase._should_complete_phase() will emit phase_completed
			log_phase_message("All redeployment complete")

func _is_in_deployment_zone(pos: Vector2, zone: Dictionary) -> bool:
	"""Check if a position is within a deployment zone polygon."""
	var polygon = zone.get("polygon", [])
	if polygon.is_empty():
		return true  # If no polygon defined, allow anywhere

	# Convert polygon to pixel coordinates if needed
	var poly_points = PackedVector2Array()
	for point in polygon:
		var px: float
		var py: float
		if point is Dictionary:
			px = point.get("x", 0) * PX_PER_INCH
			py = point.get("y", 0) * PX_PER_INCH
		elif point is Vector2:
			px = point.x * PX_PER_INCH
			py = point.y * PX_PER_INCH
		else:
			continue
		poly_points.append(Vector2(px, py))

	if poly_points.size() < 3:
		return true  # Not enough points for a polygon

	return Geometry2D.is_point_in_polygon(pos, poly_points)

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
			# Skip models from the unit being redeployed
			if unit_id == skip_unit_id:
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
	var pending = redeploy_units_pending.get(current_player, [])

	# OA-2: Check if Razgit's Magik Map redeployments remain
	var faction_mgr = get_node_or_null("/root/FactionAbilityManager")
	var razgit_remaining = 0
	if faction_mgr:
		razgit_remaining = faction_mgr.get_razgit_redeploys_remaining(current_player)

	for unit_id in pending:
		var unit = get_unit(unit_id)
		var unit_name = unit.get("meta", {}).get("name", unit_id)

		# OA-2: Check if this is a Razgit's unit and if slots remain
		var is_razgit_unit = not GameState.unit_has_redeploy(unit_id)
		if is_razgit_unit and razgit_remaining <= 0:
			# No Razgit's slots left, skip this unit
			continue

		# Can begin a redeploy
		if not active_redeploy.has(unit_id):
			actions.append({
				"type": "BEGIN_REDEPLOY",
				"unit_id": unit_id,
				"description": "Redeploy %s" % unit_name
			})

			# OA-2: Razgit's Magik Map — offer sending to Strategic Reserves
			if is_razgit_unit and faction_mgr and faction_mgr.has_razgit_magik_map(current_player):
				actions.append({
					"type": "SEND_TO_STRATEGIC_RESERVES",
					"unit_id": unit_id,
					"description": "Razgit's Magik Map: Send %s to Strategic Reserves" % unit_name
				})

		# Can skip the redeploy
		actions.append({
			"type": "SKIP_REDEPLOY",
			"unit_id": unit_id,
			"description": "Skip redeployment for %s" % unit_name
		})

	# If there are active redeploys, offer confirm
	for unit_id in active_redeploy:
		var unit = get_unit(unit_id)
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		actions.append({
			"type": "CONFIRM_REDEPLOY",
			"unit_id": unit_id,
			"description": "Confirm redeployment for %s" % unit_name
		})

	# If all pending are done, offer end phase
	var total_pending = 0
	for player in redeploy_units_pending:
		total_pending += redeploy_units_pending[player].size()

	if total_pending == 0 and active_redeploy.size() == 0:
		actions.append({
			"type": "END_REDEPLOYMENT_PHASE",
			"description": "End Redeployment Phase"
		})

	return actions

func _should_complete_phase() -> bool:
	var total_pending = 0
	for player in redeploy_units_pending:
		total_pending += redeploy_units_pending[player].size()
	return total_pending == 0 and active_redeploy.size() == 0
