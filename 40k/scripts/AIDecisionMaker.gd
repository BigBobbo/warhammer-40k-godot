class_name AIDecisionMaker
extends RefCounted

# AIDecisionMaker - Pure decision logic for the AI player
# No scene tree access, no signals. Takes data in, returns action dictionaries out.
# All methods are static for use without instantiation.

# --- Constants ---
const PIXELS_PER_INCH: float = 40.0
const ENGAGEMENT_RANGE_PX: float = 40.0  # 1 inch
const CHARGE_RANGE_PX: float = 480.0     # 12 inches
const COHERENCY_RANGE_PX: float = 80.0   # 2 inches
const BOARD_WIDTH_PX: float = 1760.0     # 44 inches
const BOARD_HEIGHT_PX: float = 2400.0    # 60 inches
const OBJECTIVE_RANGE_PX: float = 120.0  # 3 inches - objective control range in 10e
const BASE_MARGIN_PX: float = 30.0       # Safety margin from board edges

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

static func decide(phase: int, snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	print("AIDecisionMaker: Deciding for phase %d, player %d, %d available actions" % [phase, player, available_actions.size()])
	for a in available_actions:
		print("  Available: %s" % a.get("type", "?"))

	match phase:
		GameStateData.Phase.DEPLOYMENT:
			return _decide_deployment(snapshot, available_actions, player)
		GameStateData.Phase.COMMAND:
			return _decide_command(snapshot, available_actions, player)
		GameStateData.Phase.MOVEMENT:
			return _decide_movement(snapshot, available_actions, player)
		GameStateData.Phase.SHOOTING:
			return _decide_shooting(snapshot, available_actions, player)
		GameStateData.Phase.CHARGE:
			return _decide_charge(snapshot, available_actions, player)
		GameStateData.Phase.FIGHT:
			return _decide_fight(snapshot, available_actions, player)
		GameStateData.Phase.SCORING:
			return _decide_scoring(snapshot, available_actions, player)
		_:
			# Unknown phase - try to find an END action
			for action in available_actions:
				var t = action.get("type", "")
				if t.begins_with("END_"):
					return {"type": t, "_ai_description": "End phase (fallback)"}
			return {}

# =============================================================================
# DEPLOYMENT PHASE
# =============================================================================

static func _decide_deployment(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	# Filter to DEPLOY_UNIT actions
	var deploy_actions = available_actions.filter(func(a): return a.get("type") == "DEPLOY_UNIT")

	if deploy_actions.is_empty():
		# Check for END_DEPLOYMENT
		for action in available_actions:
			if action.get("type") == "END_DEPLOYMENT":
				return {"type": "END_DEPLOYMENT", "_ai_description": "End Deployment"}
		return {}  # Nothing to do (opponent deploying)

	# Pick first undeployed unit
	var action_template = deploy_actions[0]
	var unit_id = action_template.get("unit_id", "")
	var unit = snapshot.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {}

	# Calculate deployment zone bounds
	var zone_bounds = _get_deployment_zone_bounds(snapshot, player)

	# Find best position near an objective
	var objectives = _get_objectives(snapshot)
	var zone_center = Vector2(
		(zone_bounds.min_x + zone_bounds.max_x) / 2.0,
		(zone_bounds.min_y + zone_bounds.max_y) / 2.0
	)

	var best_pos = zone_center
	var best_dist = INF
	for obj_pos in objectives:
		var clamped = Vector2(
			clamp(obj_pos.x, zone_bounds.min_x, zone_bounds.max_x),
			clamp(obj_pos.y, zone_bounds.min_y, zone_bounds.max_y)
		)
		var dist = clamped.distance_to(obj_pos)
		if dist < best_dist:
			best_dist = dist
			best_pos = clamped

	# Spread units across the zone using column-based distribution
	var my_units = _get_units_for_player(snapshot, player)
	var deployed_count = 0
	for uid in my_units:
		var u = my_units[uid]
		if u.get("status", 0) != GameStateData.UnitStatus.UNDEPLOYED:
			deployed_count += 1

	var zone_width = zone_bounds.max_x - zone_bounds.min_x
	var zone_height = zone_bounds.max_y - zone_bounds.min_y
	var num_columns = maxi(3, mini(5, my_units.size()))
	var col_width = zone_width / num_columns
	var col_index = deployed_count % num_columns
	var depth_row = deployed_count / num_columns  # Which row front-to-back

	# Column center X position
	var col_center_x = zone_bounds.min_x + col_width * (col_index + 0.5)
	# Depth Y: stagger front to back within zone
	var depth_step = mini(200, int(zone_height / 3.0))
	var depth_offset = depth_row * depth_step

	# Player 1 deploys top (low Y), Player 2 deploys bottom (high Y)
	var deploy_y: float
	if zone_bounds.min_y < BOARD_HEIGHT_PX / 2.0:
		# Top zone - front edge is max_y (closer to center)
		deploy_y = zone_bounds.max_y - 80.0 - depth_offset
	else:
		# Bottom zone - front edge is min_y (closer to center)
		deploy_y = zone_bounds.min_y + 80.0 + depth_offset

	# Blend column position with objective-proximity position
	best_pos.x = col_center_x * 0.7 + best_pos.x * 0.3
	best_pos.y = clamp(deploy_y, zone_bounds.min_y + 60, zone_bounds.max_y - 60)

	# Generate formation positions
	var models = unit.get("models", [])
	var first_model = models[0] if models.size() > 0 else {}
	var base_mm = first_model.get("base_mm", 32)
	var base_type = first_model.get("base_type", "circular")
	var base_dimensions = first_model.get("base_dimensions", {})
	var positions = _generate_formation_positions(best_pos, models.size(), base_mm, zone_bounds)

	# Resolve collisions with already-deployed models
	var deployed_models = _get_all_deployed_model_positions(snapshot)
	positions = _resolve_formation_collisions(positions, base_mm, deployed_models, zone_bounds, base_type, base_dimensions)

	var rotations = []
	for i in range(models.size()):
		rotations.append(0.0)

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	return {
		"type": "DEPLOY_UNIT",
		"unit_id": unit_id,
		"model_positions": positions,
		"model_rotations": rotations,
		"_ai_description": "Deployed %s" % unit_name
	}

# =============================================================================
# COMMAND PHASE
# =============================================================================

static func _decide_command(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	# Take any pending battle-shock tests first
	for action in available_actions:
		if action.get("type") == "BATTLE_SHOCK_TEST":
			return {
				"type": "BATTLE_SHOCK_TEST",
				"unit_id": action.get("unit_id", ""),
				"_ai_description": "Battle-shock test"
			}

	# All tests done, end command phase
	return {"type": "END_COMMAND", "_ai_description": "End Command Phase"}

# =============================================================================
# MOVEMENT PHASE
# =============================================================================

static func _decide_movement(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	var action_types = {}
	for a in available_actions:
		var t = a.get("type", "")
		if not action_types.has(t):
			action_types[t] = []
		action_types[t].append(a)

	# Step 1: If CONFIRM_UNIT_MOVE is available, confirm it
	# (safety fallback — normally AIPlayer handles confirm after staging)
	if action_types.has("CONFIRM_UNIT_MOVE"):
		var a = action_types["CONFIRM_UNIT_MOVE"][0]
		var uid = a.get("actor_unit_id", a.get("unit_id", ""))
		return {
			"type": "CONFIRM_UNIT_MOVE",
			"actor_unit_id": uid,
			"_ai_description": "Confirmed move"
		}

	# Step 2: Check if any unit can begin moving
	var begin_types = ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK", "REMAIN_STATIONARY"]
	var can_begin = false
	for bt in begin_types:
		if action_types.has(bt):
			can_begin = true
			break

	if can_begin:
		return _select_movement_action(snapshot, available_actions, player)

	# Step 3: End movement phase
	return {"type": "END_MOVEMENT", "_ai_description": "End Movement Phase"}

static func _select_movement_action(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	# Collect units that can begin moving
	var movable_units = {}  # unit_id -> list of available move types
	for a in available_actions:
		var t = a.get("type", "")
		if t in ["BEGIN_NORMAL_MOVE", "BEGIN_ADVANCE", "BEGIN_FALL_BACK", "REMAIN_STATIONARY"]:
			var uid = a.get("actor_unit_id", a.get("unit_id", ""))
			if uid != "":
				if not movable_units.has(uid):
					movable_units[uid] = []
				movable_units[uid].append(t)

	if movable_units.is_empty():
		return {"type": "END_MOVEMENT", "_ai_description": "End Movement Phase"}

	var objectives = _get_objectives(snapshot)
	var enemies = _get_enemy_units(snapshot, player)

	# Evaluate each unit: score by distance to nearest objective (process near units first
	# so they remain stationary quickly, then process far units that need to move)
	var scored_units = []
	for unit_id in movable_units:
		var unit = snapshot.get("units", {}).get(unit_id, {})
		var centroid = _get_unit_centroid(unit)
		if centroid == Vector2.INF:
			continue
		var nearest_dist = _nearest_objective_distance(centroid, objectives)
		scored_units.append({
			"unit_id": unit_id,
			"obj_dist": nearest_dist,
			"move_types": movable_units[unit_id]
		})

	# Sort: units nearest to objectives first (remain stationary), then farthest (need to move)
	scored_units.sort_custom(func(a, b): return a.obj_dist < b.obj_dist)

	for scored in scored_units:
		var unit_id = scored.unit_id
		var move_types = scored.move_types
		var unit = snapshot.get("units", {}).get(unit_id, {})
		var unit_name = unit.get("meta", {}).get("name", unit_id)

		# --- Engaged units: fall back ---
		if "BEGIN_FALL_BACK" in move_types and not "BEGIN_NORMAL_MOVE" in move_types:
			print("AIDecisionMaker: %s is engaged, falling back" % unit_name)
			return {
				"type": "BEGIN_FALL_BACK",
				"actor_unit_id": unit_id,
				"_ai_description": "%s falls back (engaged with enemy)" % unit_name
			}

		# --- Already near an objective: remain stationary ---
		if scored.obj_dist <= OBJECTIVE_RANGE_PX:
			if "REMAIN_STATIONARY" in move_types:
				var dist_inches = scored.obj_dist / PIXELS_PER_INCH
				print("AIDecisionMaker: %s is within 3\" of objective (%.1f px), holding position" % [unit_name, scored.obj_dist])
				return {
					"type": "REMAIN_STATIONARY",
					"actor_unit_id": unit_id,
					"_ai_description": "%s holds objective (%.1f\" away)" % [unit_name, dist_inches]
				}

		# --- Move toward the nearest objective ---
		if "BEGIN_NORMAL_MOVE" in move_types:
			var move_inches = float(unit.get("meta", {}).get("stats", {}).get("move", 6))
			var obj_dist_inches = scored.obj_dist / PIXELS_PER_INCH
			var model_destinations = _compute_movement_toward_objective(
				unit, objectives, move_inches, snapshot, enemies
			)

			if not model_destinations.is_empty():
				print("AIDecisionMaker: %s moving toward objective (M: %.0f\")" % [unit_name, move_inches])
				return {
					"type": "BEGIN_NORMAL_MOVE",
					"actor_unit_id": unit_id,
					"_ai_model_destinations": model_destinations,
					"_ai_description": "%s moves toward objective (M: %d\", obj: %.1f\" away)" % [unit_name, int(move_inches), obj_dist_inches]
				}
			else:
				print("AIDecisionMaker: %s cannot find valid move, remaining stationary" % unit_name)

		# --- Fallback: remain stationary ---
		if "REMAIN_STATIONARY" in move_types:
			var reason = "no valid move found"
			if objectives.is_empty():
				reason = "no objectives on board"
			elif enemies.size() > 0:
				reason = "all paths blocked or near enemies"
			return {
				"type": "REMAIN_STATIONARY",
				"actor_unit_id": unit_id,
				"_ai_description": "%s remains stationary (%s)" % [unit_name, reason]
			}

	return {"type": "END_MOVEMENT", "_ai_description": "End Movement Phase"}

# --- Movement helpers ---

static func _nearest_objective_distance(pos: Vector2, objectives: Array) -> float:
	var best = INF
	for obj_pos in objectives:
		var d = pos.distance_to(obj_pos)
		if d < best:
			best = d
	return best

static func _compute_movement_toward_objective(
	unit: Dictionary, objectives: Array, move_inches: float,
	snapshot: Dictionary, enemies: Dictionary
) -> Dictionary:
	# Returns: {model_id: [x, y], ...} or empty dict if no valid move

	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return {}
	if objectives.is_empty():
		return {}

	var centroid = _get_unit_centroid(unit)
	if centroid == Vector2.INF:
		return {}

	# Find the nearest objective
	var best_objective = objectives[0]
	var best_dist = centroid.distance_to(objectives[0])
	for i in range(1, objectives.size()):
		var d = centroid.distance_to(objectives[i])
		if d < best_dist:
			best_dist = d
			best_objective = objectives[i]

	# Calculate movement vector toward objective
	var direction = (best_objective - centroid).normalized()
	var move_px = move_inches * PIXELS_PER_INCH
	# Don't overshoot the objective — stop at the objective center
	var actual_move_px = min(move_px, best_dist)
	var move_vector = direction * actual_move_px

	# Get terrain features for blocking checks
	var terrain_features = snapshot.get("board", {}).get("terrain_features", [])
	var unit_keywords = unit.get("meta", {}).get("keywords", [])

	# Check if the direct path is blocked by terrain
	var final_move_vector = _find_unblocked_move(
		centroid, move_vector, actual_move_px, unit_keywords, terrain_features
	)

	if final_move_vector == Vector2.ZERO:
		print("AIDecisionMaker: All movement paths blocked by terrain")
		return {}

	# Compute destination for each model by applying the same translation
	var destinations = {}
	var all_valid = true

	for model in alive_models:
		var model_id = model.get("id", "")
		if model_id == "":
			continue
		var model_pos = _get_model_position(model)
		if model_pos == Vector2.INF:
			continue
		var dest = model_pos + final_move_vector

		# Clamp to board bounds with margin
		dest.x = clamp(dest.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		dest.y = clamp(dest.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

		# Check if destination is within engagement range of any enemy
		if _is_position_near_enemy(dest, enemies, unit):
			all_valid = false
			break

		destinations[model_id] = [dest.x, dest.y]

	# If any model would end in engagement range, try a shorter move
	if not all_valid:
		destinations = _try_shorter_move(alive_models, final_move_vector, enemies, unit)

	return destinations

static func _find_unblocked_move(
	centroid: Vector2, move_vector: Vector2, move_distance_px: float,
	unit_keywords: Array, terrain_features: Array
) -> Vector2:
	# Try the direct path first
	if not _path_blocked_by_terrain(centroid, centroid + move_vector, unit_keywords, terrain_features):
		return move_vector

	print("AIDecisionMaker: Direct path blocked, trying alternate directions")

	# Try angled alternatives: ±30°, ±60°, ±90°
	var base_direction = move_vector.normalized()
	var angles_to_try = [
		deg_to_rad(30), deg_to_rad(-30),
		deg_to_rad(60), deg_to_rad(-60),
		deg_to_rad(90), deg_to_rad(-90)
	]

	for angle in angles_to_try:
		var rotated_dir = base_direction.rotated(angle)
		var alt_vector = rotated_dir * move_distance_px
		if not _path_blocked_by_terrain(centroid, centroid + alt_vector, unit_keywords, terrain_features):
			print("AIDecisionMaker: Found unblocked path at %.0f degrees" % rad_to_deg(angle))
			return alt_vector

	# Try moving at half distance in the original direction
	var half_vector = move_vector * 0.5
	if not _path_blocked_by_terrain(centroid, centroid + half_vector, unit_keywords, terrain_features):
		print("AIDecisionMaker: Moving at half distance to avoid terrain")
		return half_vector

	# All paths blocked
	return Vector2.ZERO

static func _path_blocked_by_terrain(
	from: Vector2, to: Vector2, unit_keywords: Array, terrain_features: Array
) -> bool:
	for terrain in terrain_features:
		# Check if the unit can move through this terrain type
		var can_move_through = terrain.get("can_move_through", {})
		var unit_can_pass = false
		for keyword in unit_keywords:
			if can_move_through.get(keyword, false):
				unit_can_pass = true
				break
		# FLY units can always pass over terrain
		if "FLY" in unit_keywords:
			unit_can_pass = true

		if unit_can_pass:
			continue

		# Check if the line intersects this terrain polygon
		var polygon = terrain.get("polygon", [])
		if polygon is PackedVector2Array:
			if _line_intersects_polygon(from, to, polygon):
				return true
		elif polygon is Array and polygon.size() >= 3:
			# Convert Array to points for checking
			var packed = PackedVector2Array()
			for p in polygon:
				if p is Vector2:
					packed.append(p)
				elif p is Dictionary:
					packed.append(Vector2(float(p.get("x", 0)), float(p.get("y", 0))))
			if _line_intersects_polygon(from, to, packed):
				return true

	return false

static func _line_intersects_polygon(from: Vector2, to: Vector2, polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3:
		return false

	# Check if line segment intersects any edge of the polygon
	for i in range(polygon.size()):
		var edge_start = polygon[i]
		var edge_end = polygon[(i + 1) % polygon.size()]
		if Geometry2D.segment_intersects_segment(from, to, edge_start, edge_end):
			return true

	# Also check if starting point is inside the polygon (already in terrain)
	if Geometry2D.is_point_in_polygon(to, polygon):
		return true

	return false

static func _is_position_near_enemy(pos: Vector2, enemies: Dictionary, own_unit: Dictionary) -> bool:
	# Check if position is within engagement range (1") of any enemy model
	var own_models = own_unit.get("models", [])
	var own_base_mm = own_models[0].get("base_mm", 32) if own_models.size() > 0 else 32
	var own_radius_px = (own_base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)

	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		for model in enemy.get("models", []):
			if not model.get("alive", true):
				continue
			var enemy_pos = _get_model_position(model)
			if enemy_pos == Vector2.INF:
				continue
			var dist = pos.distance_to(enemy_pos)
			# Use engagement range + base radii for proper edge-to-edge check
			var enemy_base_mm = model.get("base_mm", 32)
			var enemy_radius_px = (enemy_base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)
			var min_dist = own_radius_px + enemy_radius_px + ENGAGEMENT_RANGE_PX
			if dist < min_dist:
				return true
	return false

static func _try_shorter_move(
	alive_models: Array, move_vector: Vector2,
	enemies: Dictionary, unit: Dictionary
) -> Dictionary:
	# Try progressively shorter moves: 75%, 50%, 25% of the original
	for fraction in [0.75, 0.5, 0.25]:
		var shorter = move_vector * fraction
		var destinations = {}
		var valid = true

		for model in alive_models:
			var model_id = model.get("id", "")
			if model_id == "":
				continue
			var model_pos = _get_model_position(model)
			if model_pos == Vector2.INF:
				continue
			var dest = model_pos + shorter
			dest.x = clamp(dest.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
			dest.y = clamp(dest.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

			if _is_position_near_enemy(dest, enemies, unit):
				valid = false
				break
			destinations[model_id] = [dest.x, dest.y]

		if valid and not destinations.is_empty():
			print("AIDecisionMaker: Using shorter move at %.0f%% to avoid enemies" % (fraction * 100))
			return destinations

	# Can't find safe move at any distance
	return {}

# =============================================================================
# SHOOTING PHASE
# =============================================================================

static func _decide_shooting(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	var action_types = {}
	for a in available_actions:
		var t = a.get("type", "")
		if not action_types.has(t):
			action_types[t] = []
		action_types[t].append(a)

	# Step 1: Handle saves if needed
	if action_types.has("APPLY_SAVES"):
		return {"type": "APPLY_SAVES", "payload": {"save_results_list": []}, "_ai_description": "Applying saves"}

	# Step 2: Continue weapon sequence if needed
	if action_types.has("CONTINUE_SEQUENCE"):
		return {"type": "CONTINUE_SEQUENCE", "_ai_description": "Continue weapon sequence"}

	# Step 3: Resolve shooting if ready
	if action_types.has("RESOLVE_SHOOTING"):
		return {"type": "RESOLVE_SHOOTING", "_ai_description": "Resolve shooting"}

	# Step 4: Confirm targets if pending
	if action_types.has("CONFIRM_TARGETS"):
		return {"type": "CONFIRM_TARGETS", "_ai_description": "Confirm targets"}

	# Step 5: Use the SHOOT action for a full shooting sequence
	# This is the cleanest path - select + assign + confirm in one action
	if action_types.has("SELECT_SHOOTER"):
		var shooter_action = action_types["SELECT_SHOOTER"][0]
		var unit_id = shooter_action.get("actor_unit_id", shooter_action.get("unit_id", ""))

		if unit_id == "":
			return {"type": "END_SHOOTING", "_ai_description": "End Shooting Phase"}

		var unit = snapshot.get("units", {}).get(unit_id, {})
		var unit_name = unit.get("meta", {}).get("name", unit_id)

		# Get weapons for this unit
		var weapons = unit.get("meta", {}).get("weapons", [])
		var ranged_weapons = []
		for w in weapons:
			if w.get("type", "").to_lower() == "ranged":
				ranged_weapons.append(w)

		if ranged_weapons.is_empty():
			# No ranged weapons, skip this unit
			return {
				"type": "SKIP_UNIT",
				"actor_unit_id": unit_id,
				"_ai_description": "Skipped %s — no ranged weapons" % unit_name
			}

		# Find the best target for each weapon
		var enemies = _get_enemy_units(snapshot, player)
		if enemies.is_empty():
			return {"type": "END_SHOOTING", "_ai_description": "End Shooting Phase (no targets)"}

		# Build assignments: assign all ranged weapons to best target
		var assignments = []
		for weapon in ranged_weapons:
			var weapon_name = weapon.get("name", "")
			var weapon_id = _generate_weapon_id(weapon_name)

			# Score each enemy target
			var best_target_id = ""
			var best_score = -1.0
			for enemy_id in enemies:
				var enemy = enemies[enemy_id]
				var score = _score_shooting_target(weapon, enemy, snapshot)
				if score > best_score:
					best_score = score
					best_target_id = enemy_id

			if best_target_id != "" and best_score > 0:
				assignments.append({
					"weapon_id": weapon_id,
					"target_unit_id": best_target_id,
					"model_ids": []
				})

		if assignments.is_empty():
			return {
				"type": "SKIP_UNIT",
				"actor_unit_id": unit_id,
				"_ai_description": "Skipped %s — no valid targets in range" % unit_name
			}

		# Use the SHOOT action for a complete shooting sequence
		# Build target summary
		var target_names = []
		for assignment in assignments:
			var tid = assignment.get("target_unit_id", "")
			var target = snapshot.get("units", {}).get(tid, {})
			var tname = target.get("meta", {}).get("name", tid)
			if tname not in target_names:
				target_names.append(tname)
		var target_summary = ", ".join(target_names)
		return {
			"type": "SHOOT",
			"actor_unit_id": unit_id,
			"payload": {
				"assignments": assignments
			},
			"_ai_description": "%s shoots at %s (%d weapon(s))" % [unit_name, target_summary, assignments.size()]
		}

	# No shooters left, end phase
	return {"type": "END_SHOOTING", "_ai_description": "End Shooting Phase"}

# =============================================================================
# CHARGE PHASE
# =============================================================================

static func _decide_charge(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	var action_types = {}
	for a in available_actions:
		var t = a.get("type", "")
		if not action_types.has(t):
			action_types[t] = []
		action_types[t].append(a)

	# Step 1: If charge roll is needed, roll
	if action_types.has("CHARGE_ROLL"):
		var a = action_types["CHARGE_ROLL"][0]
		var uid = a.get("actor_unit_id", "")
		return {
			"type": "CHARGE_ROLL",
			"actor_unit_id": uid,
			"_ai_description": "Charge roll"
		}

	# Step 2: If we can declare charges, evaluate
	if action_types.has("DECLARE_CHARGE"):
		# For initial implementation, skip all charges since APPLY_CHARGE_MOVE
		# requires complex model positioning that needs geometric validation.
		# Instead, skip each chargeable unit.
		if action_types.has("SKIP_CHARGE"):
			var a = action_types["SKIP_CHARGE"][0]
			var uid = a.get("actor_unit_id", "")
			var unit = snapshot.get("units", {}).get(uid, {})
			var unit_name = unit.get("meta", {}).get("name", uid)
			return {
				"type": "SKIP_CHARGE",
				"actor_unit_id": uid,
				"_ai_description": "Skipped charge for %s (not implemented)" % unit_name
			}

	# Step 3: End charge phase
	return {"type": "END_CHARGE", "_ai_description": "End Charge Phase"}

# =============================================================================
# FIGHT PHASE
# =============================================================================

static func _decide_fight(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	var action_types = {}
	for a in available_actions:
		var t = a.get("type", "")
		if not action_types.has(t):
			action_types[t] = []
		action_types[t].append(a)

	# Step 1: If we can roll dice (confirmed attacks ready), roll them
	if action_types.has("ROLL_DICE"):
		return {"type": "ROLL_DICE", "_ai_description": "Roll fight dice"}

	# Step 2: If we can confirm attacks, confirm them
	if action_types.has("CONFIRM_AND_RESOLVE_ATTACKS"):
		return {"type": "CONFIRM_AND_RESOLVE_ATTACKS", "_ai_description": "Confirm fight attacks"}

	# Step 3: If pile-in or assign attacks available, handle them
	if action_types.has("ASSIGN_ATTACKS_UI") or action_types.has("PILE_IN"):
		# We need to assign attacks for the active fighter
		# First pile in (empty movements = skip pile in)
		if action_types.has("PILE_IN"):
			var a = action_types["PILE_IN"][0]
			var uid = a.get("unit_id", "")
			return {
				"type": "PILE_IN",
				"unit_id": uid,
				"actor_unit_id": uid,
				"movements": {},
				"_ai_description": "Pile in (hold position)"
			}

		# Then assign attacks
		if action_types.has("ASSIGN_ATTACKS_UI"):
			var a = action_types["ASSIGN_ATTACKS_UI"][0]
			var uid = a.get("unit_id", "")
			return _assign_fight_attacks(snapshot, uid, player)

	# Step 4: If we need to select a fighter, select one
	if action_types.has("SELECT_FIGHTER"):
		var a = action_types["SELECT_FIGHTER"][0]
		var uid = a.get("unit_id", "")
		var unit = snapshot.get("units", {}).get(uid, {})
		var unit_name = unit.get("meta", {}).get("name", uid)
		return {
			"type": "SELECT_FIGHTER",
			"unit_id": uid,
			"_ai_description": "Select %s to fight" % unit_name
		}

	# Step 5: Consolidate if available
	if action_types.has("CONSOLIDATE"):
		var a = action_types["CONSOLIDATE"][0]
		var uid = a.get("unit_id", "")
		return {
			"type": "CONSOLIDATE",
			"unit_id": uid,
			"movements": {},
			"_ai_description": "Consolidate (hold position)"
		}

	# Step 6: End fight phase
	if action_types.has("END_FIGHT"):
		return {"type": "END_FIGHT", "_ai_description": "End Fight Phase"}

	return {}

static func _assign_fight_attacks(snapshot: Dictionary, unit_id: String, player: int) -> Dictionary:
	var unit = snapshot.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {}

	# Get melee weapons for this unit
	var weapons = unit.get("meta", {}).get("weapons", [])
	var melee_weapon = null
	for w in weapons:
		if w.get("type", "").to_lower() == "melee":
			melee_weapon = w
			break

	# Default to close combat weapon
	var weapon_id = "close_combat_weapon"
	if melee_weapon:
		weapon_id = _generate_weapon_id(melee_weapon.get("name", "Close combat weapon"))

	# Find an enemy unit in engagement range
	var enemies = _get_enemy_units(snapshot, player)
	var best_target_id = ""
	var best_dist = INF
	var unit_centroid = _get_unit_centroid(unit)

	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		var enemy_centroid = _get_unit_centroid(enemy)
		if enemy_centroid == Vector2.INF:
			continue
		var dist = unit_centroid.distance_to(enemy_centroid)
		if dist < best_dist:
			best_dist = dist
			best_target_id = enemy_id

	if best_target_id == "":
		return {}

	return {
		"type": "ASSIGN_ATTACKS",
		"unit_id": unit_id,
		"target_id": best_target_id,
		"weapon_id": weapon_id,
		"_ai_description": "Assign melee attacks"
	}

# =============================================================================
# SCORING PHASE
# =============================================================================

static func _decide_scoring(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	return {"type": "END_SCORING", "_ai_description": "End Turn"}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

static func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position", null)
	if pos == null:
		return Vector2.INF
	if pos is Vector2:
		return pos
	return Vector2(float(pos.get("x", 0)), float(pos.get("y", 0)))

static func _get_alive_models(unit: Dictionary) -> Array:
	var alive = []
	for model in unit.get("models", []):
		if model.get("alive", true):
			alive.append(model)
	return alive

static func _get_alive_models_with_positions(unit: Dictionary) -> Array:
	var alive = []
	for model in unit.get("models", []):
		if model.get("alive", true) and model.get("position", null) != null:
			alive.append(model)
	return alive

static func _get_unit_centroid(unit: Dictionary) -> Vector2:
	var alive = _get_alive_models_with_positions(unit)
	if alive.is_empty():
		return Vector2.INF
	var sum_val = Vector2.ZERO
	for model in alive:
		sum_val += _get_model_position(model)
	return sum_val / alive.size()

static func _get_objectives(snapshot: Dictionary) -> Array:
	var objectives = []
	for obj in snapshot.get("board", {}).get("objectives", []):
		var pos = obj.get("position", null)
		if pos:
			if pos is Vector2:
				objectives.append(pos)
			else:
				objectives.append(Vector2(float(pos.get("x", 0)), float(pos.get("y", 0))))
	return objectives

static func _get_units_for_player(snapshot: Dictionary, player: int) -> Dictionary:
	var result = {}
	for unit_id in snapshot.get("units", {}):
		var unit = snapshot.units[unit_id]
		if unit.get("owner", 0) == player:
			result[unit_id] = unit
	return result

static func _get_enemy_units(snapshot: Dictionary, player: int) -> Dictionary:
	var result = {}
	for unit_id in snapshot.get("units", {}):
		var unit = snapshot.units[unit_id]
		if unit.get("owner", 0) != player:
			var status = unit.get("status", 0)
			if status == GameStateData.UnitStatus.UNDEPLOYED or status == GameStateData.UnitStatus.IN_RESERVES:
				continue
			var has_alive = false
			for model in unit.get("models", []):
				if model.get("alive", true):
					has_alive = true
					break
			if has_alive:
				result[unit_id] = unit
	return result

static func _get_deployment_zone_bounds(snapshot: Dictionary, player: int) -> Dictionary:
	var zones = snapshot.get("board", {}).get("deployment_zones", [])
	for zone in zones:
		if zone.get("player", 0) == player:
			var vertices = zone.get("vertices", [])
			if not vertices.is_empty():
				var min_x = INF
				var max_x = -INF
				var min_y = INF
				var max_y = -INF
				for v in vertices:
					var vx: float
					var vy: float
					if v is Vector2:
						vx = v.x
						vy = v.y
					else:
						vx = float(v.get("x", 0))
						vy = float(v.get("y", 0))
					min_x = min(min_x, vx)
					max_x = max(max_x, vx)
					min_y = min(min_y, vy)
					max_y = max(max_y, vy)
				return {"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y}

	# Fallback: standard Hammer and Anvil zones
	if player == 1:
		return {"min_x": 40.0, "max_x": 1720.0, "min_y": 10.0, "max_y": 470.0}
	else:
		return {"min_x": 40.0, "max_x": 1720.0, "min_y": 1930.0, "max_y": 2390.0}

static func _generate_formation_positions(centroid: Vector2, num_models: int,
										base_mm: int, zone_bounds: Dictionary) -> Array:
	var positions = []
	var base_radius_px = (base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)
	var spacing = base_radius_px * 2.0 + 10.0  # Base diameter + small gap

	var cols = mini(5, num_models)
	var rows = ceili(float(num_models) / cols)

	var start_x = centroid.x - (cols - 1) * spacing / 2.0
	var start_y = centroid.y - (rows - 1) * spacing / 2.0

	for i in range(num_models):
		var row = i / cols
		var col = i % cols
		var pos = Vector2(start_x + col * spacing, start_y + row * spacing)

		# Clamp to zone bounds with margin
		var margin = base_radius_px + 5.0
		pos.x = clamp(pos.x, zone_bounds.get("min_x", margin) + margin,
					zone_bounds.get("max_x", BOARD_WIDTH_PX - margin) - margin)
		pos.y = clamp(pos.y, zone_bounds.get("min_y", margin) + margin,
					zone_bounds.get("max_y", BOARD_HEIGHT_PX - margin) - margin)

		positions.append(pos)

	return positions

# --- Collision detection utilities for deployment ---

static func _get_all_deployed_model_positions(snapshot: Dictionary) -> Array:
	"""Returns array of {position: Vector2, base_mm: int, base_type: String, base_dimensions: Dictionary}
	for every deployed model on the board."""
	var deployed = []
	for unit_id in snapshot.get("units", {}):
		var unit = snapshot.units[unit_id]
		if unit.get("status", 0) != GameStateData.UnitStatus.DEPLOYED:
			continue
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var pos_data = model.get("position", null)
			if pos_data == null:
				continue
			var pos: Vector2
			if pos_data is Vector2:
				pos = pos_data
			else:
				pos = Vector2(float(pos_data.get("x", 0)), float(pos_data.get("y", 0)))
			deployed.append({
				"position": pos,
				"base_mm": model.get("base_mm", 32),
				"base_type": model.get("base_type", "circular"),
				"base_dimensions": model.get("base_dimensions", {}),
				"rotation": model.get("rotation", 0.0)
			})
	return deployed

static func _model_bounding_radius_px(base_mm: int, base_type: String = "circular", base_dimensions: Dictionary = {}) -> float:
	"""Returns conservative bounding circle radius in pixels for any base type."""
	var mm_to_px = PIXELS_PER_INCH / 25.4
	match base_type:
		"circular":
			return (base_mm / 2.0) * mm_to_px
		"rectangular", "oval":
			var length_mm = base_dimensions.get("length", base_mm)
			var width_mm = base_dimensions.get("width", base_mm * 0.6)
			# Bounding circle = half the diagonal
			var diag_mm = sqrt(length_mm * length_mm + width_mm * width_mm)
			return (diag_mm / 2.0) * mm_to_px
		_:
			return (base_mm / 2.0) * mm_to_px

static func _position_collides_with_deployed(pos: Vector2, base_mm: int, deployed_models: Array, min_gap_px: float = 4.0, base_type: String = "circular", base_dimensions: Dictionary = {}) -> bool:
	"""Check if a position would collide with any deployed model using bounding-circle approximation."""
	var my_radius = _model_bounding_radius_px(base_mm, base_type, base_dimensions)
	for dm in deployed_models:
		var other_radius = _model_bounding_radius_px(
			dm.get("base_mm", 32),
			dm.get("base_type", "circular"),
			dm.get("base_dimensions", {})
		)
		var min_dist = my_radius + other_radius + min_gap_px
		if pos.distance_to(dm.position) < min_dist:
			return true
	return false

static func _resolve_formation_collisions(positions: Array, base_mm: int, deployed_models: Array, zone_bounds: Dictionary, base_type: String = "circular", base_dimensions: Dictionary = {}) -> Array:
	"""For each position that collides, spiral-search for the nearest free spot.
	Also prevents intra-formation overlap."""
	var resolved = []
	# Track positions we've already placed in this formation
	var formation_placed: Array = []  # Array of {position, base_mm, base_type, base_dimensions}
	var mm_to_px = PIXELS_PER_INCH / 25.4
	var my_radius = _model_bounding_radius_px(base_mm, base_type, base_dimensions)
	var margin = my_radius + 5.0
	var step = my_radius * 2.0 + 8.0  # Spiral step size

	for pos in positions:
		# Combine deployed models + already-placed formation models for collision
		var all_obstacles = deployed_models + formation_placed

		if not _position_collides_with_deployed(pos, base_mm, all_obstacles, 4.0, base_type, base_dimensions):
			# No collision, use as-is
			resolved.append(pos)
			formation_placed.append({
				"position": pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions
			})
			continue

		# Spiral search for a free spot
		var found = false
		for ring in range(1, 8):  # Up to 7 rings outward
			var ring_radius = step * ring
			var points_in_ring = maxi(8, ring * 8)
			for p_idx in range(points_in_ring):
				var angle = (2.0 * PI * p_idx) / points_in_ring
				var candidate = Vector2(
					pos.x + cos(angle) * ring_radius,
					pos.y + sin(angle) * ring_radius
				)
				# Clamp to zone bounds
				candidate.x = clamp(candidate.x, zone_bounds.get("min_x", margin) + margin, zone_bounds.get("max_x", BOARD_WIDTH_PX - margin) - margin)
				candidate.y = clamp(candidate.y, zone_bounds.get("min_y", margin) + margin, zone_bounds.get("max_y", BOARD_HEIGHT_PX - margin) - margin)

				if not _position_collides_with_deployed(candidate, base_mm, all_obstacles, 4.0, base_type, base_dimensions):
					resolved.append(candidate)
					formation_placed.append({
						"position": candidate,
						"base_mm": base_mm,
						"base_type": base_type,
						"base_dimensions": base_dimensions
					})
					found = true
					break
			if found:
				break

		if not found:
			# Last resort: use original position (will likely fail validation, but retry logic will handle it)
			print("AIDecisionMaker: WARNING - Could not find collision-free position for model, using original")
			resolved.append(pos)
			formation_placed.append({
				"position": pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions
			})

	return resolved

static func _generate_weapon_id(weapon_name: String) -> String:
	var weapon_id = weapon_name.to_lower()
	weapon_id = weapon_id.replace(" ", "_")
	weapon_id = weapon_id.replace("-", "_")
	weapon_id = weapon_id.replace("–", "_")
	weapon_id = weapon_id.replace("'", "")
	return weapon_id

# =============================================================================
# SCORING FUNCTIONS
# =============================================================================

static func _wound_probability(strength: int, toughness: int) -> float:
	if strength >= toughness * 2:
		return 5.0 / 6.0  # 2+
	elif strength > toughness:
		return 4.0 / 6.0  # 3+
	elif strength == toughness:
		return 3.0 / 6.0  # 4+
	elif strength * 2 <= toughness:
		return 1.0 / 6.0  # 6+
	else:
		return 2.0 / 6.0  # 5+

static func _hit_probability(skill: int) -> float:
	if skill <= 1:
		return 1.0
	if skill >= 7:
		return 0.0
	return (7.0 - skill) / 6.0

static func _save_probability(save_val: int, ap: int) -> float:
	var modified_save = save_val + abs(ap)
	if modified_save >= 7:
		return 0.0
	if modified_save <= 1:
		return 1.0
	return (7.0 - modified_save) / 6.0

static func _score_shooting_target(weapon: Dictionary, target_unit: Dictionary, snapshot: Dictionary) -> float:
	var attacks_str = weapon.get("attacks", "1")
	var attacks = float(attacks_str) if attacks_str.is_valid_float() else 1.0

	var bs_str = weapon.get("ballistic_skill", "4")
	var bs = int(bs_str) if bs_str.is_valid_int() else 4

	var strength_str = weapon.get("strength", "4")
	var strength = int(strength_str) if strength_str.is_valid_int() else 4

	var ap_str = weapon.get("ap", "0")
	var ap = 0
	if ap_str.begins_with("-"):
		var ap_num = ap_str.substr(1)
		ap = int(ap_num) if ap_num.is_valid_int() else 0
	else:
		ap = int(ap_str) if ap_str.is_valid_int() else 0

	var damage_str = weapon.get("damage", "1")
	var damage = float(damage_str) if damage_str.is_valid_float() else 1.0

	var toughness = target_unit.get("meta", {}).get("stats", {}).get("toughness", 4)
	var target_save = target_unit.get("meta", {}).get("stats", {}).get("save", 4)

	var p_hit = _hit_probability(bs)
	var p_wound = _wound_probability(strength, toughness)
	var p_unsaved = 1.0 - _save_probability(target_save, ap)

	var expected_damage = attacks * p_hit * p_wound * p_unsaved * damage

	# Bonus: target below half strength (finish it off)
	var alive_count = _get_alive_models(target_unit).size()
	var total_count = target_unit.get("models", []).size()
	if total_count > 0 and alive_count * 2 < total_count:
		expected_damage *= 1.5

	# Bonus: target has CHARACTER keyword
	var keywords = target_unit.get("meta", {}).get("keywords", [])
	if "CHARACTER" in keywords:
		expected_damage *= 1.2

	return expected_damage
