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
const OBJECTIVE_CONTROL_RANGE_PX: float = 151.5  # 3.79" (3" + 20mm marker radius) in pixels
const BASE_MARGIN_PX: float = 30.0       # Safety margin from board edges

# Movement AI tuning weights
const WEIGHT_UNCONTROLLED_OBJ: float = 10.0
const WEIGHT_CONTESTED_OBJ: float = 8.0
const WEIGHT_ENEMY_WEAK_OBJ: float = 7.0
const WEIGHT_HOME_UNDEFENDED: float = 9.0
const WEIGHT_ENEMY_STRONG_OBJ: float = -5.0
const WEIGHT_ALREADY_HELD_OBJ: float = -8.0
const WEIGHT_SCORING_URGENCY: float = 3.0
const WEIGHT_OC_EFFICIENCY: float = 2.0

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

static func decide(phase: int, snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	print("AIDecisionMaker: Deciding for phase %d, player %d, %d available actions" % [phase, player, available_actions.size()])
	for a in available_actions:
		print("  Available: %s" % a.get("type", "?"))

	match phase:
		GameStateData.Phase.FORMATIONS:
			return _decide_formations(snapshot, available_actions, player)
		GameStateData.Phase.DEPLOYMENT:
			return _decide_deployment(snapshot, available_actions, player)
		GameStateData.Phase.SCOUT:
			return _decide_scout(snapshot, available_actions, player)
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
# FORMATIONS PHASE
# =============================================================================

static func _decide_formations(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	# AI strategy: confirm formations immediately (no leader attachments, transports, or reserves for now)
	# Future improvement: evaluate leader attachments, transport embarkations, and reserve declarations
	for action in available_actions:
		if action.get("type") == "CONFIRM_FORMATIONS":
			return {
				"type": "CONFIRM_FORMATIONS",
				"player": player,
				"_ai_description": "AI confirms battle formations"
			}
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
# SCOUT PHASE
# =============================================================================

static func _decide_scout(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	# AI strategy: Skip all scout moves for now (simple fallback)
	# Future improvement: move scouts toward nearest objective
	for action in available_actions:
		if action.get("type") == "SKIP_SCOUT_MOVE":
			return {
				"type": "SKIP_SCOUT_MOVE",
				"unit_id": action.get("unit_id", ""),
				"_ai_description": "Skip Scout move for %s" % action.get("unit_id", "")
			}

	# If all scouts handled, end phase
	for action in available_actions:
		if action.get("type") == "END_SCOUT_PHASE":
			return {"type": "END_SCOUT_PHASE", "_ai_description": "End Scout Phase"}

	return {}

# =============================================================================
# COMMAND PHASE
# =============================================================================

static func _decide_command(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	# Handle pending Command Re-roll decisions first
	for action in available_actions:
		if action.get("type") == "USE_COMMAND_REROLL":
			# AI heuristic: use reroll if the roll was within 3 of the leadership value
			# (i.e. a reroll has a reasonable chance of passing)
			return {
				"type": "USE_COMMAND_REROLL",
				"_ai_description": "Command Re-roll (battle-shock)"
			}
	for action in available_actions:
		if action.get("type") == "DECLINE_COMMAND_REROLL":
			# Fallback: if USE_COMMAND_REROLL wasn't in the list, decline
			return {
				"type": "DECLINE_COMMAND_REROLL",
				"_ai_description": "Decline re-roll"
			}

	# Take any pending battle-shock tests
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
	var friendly_units = _get_units_for_player(snapshot, player)
	var battle_round = snapshot.get("battle_round", 1)

	# =========================================================================
	# PHASE 1: GLOBAL OBJECTIVE EVALUATION
	# =========================================================================
	var obj_evaluations = _evaluate_all_objectives(snapshot, objectives, player, enemies, friendly_units, battle_round)

	# =========================================================================
	# PHASE 2: UNIT-TO-OBJECTIVE ASSIGNMENT
	# =========================================================================
	var assignments = _assign_units_to_objectives(
		snapshot, movable_units, obj_evaluations, objectives, enemies, friendly_units, player, battle_round
	)

	# =========================================================================
	# PHASE 3: EXECUTE BEST ASSIGNMENT
	# =========================================================================
	# Process units: engaged units first (must decide immediately), then by assignment priority
	var engaged_units = []
	var assigned_units = []

	for unit_id in movable_units:
		var move_types = movable_units[unit_id]
		var is_engaged = "BEGIN_FALL_BACK" in move_types and not "BEGIN_NORMAL_MOVE" in move_types
		if is_engaged:
			engaged_units.append(unit_id)
		else:
			assigned_units.append(unit_id)

	# --- Handle engaged units first ---
	for unit_id in engaged_units:
		var unit = snapshot.get("units", {}).get(unit_id, {})
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var move_types = movable_units[unit_id]
		var decision = _decide_engaged_unit(unit, unit_id, unit_name, move_types, objectives, enemies, snapshot, player)
		if not decision.is_empty():
			return decision

	# --- Sort assigned units by priority (highest assignment score first) ---
	assigned_units.sort_custom(func(a, b):
		var score_a = assignments.get(a, {}).get("score", 0.0)
		var score_b = assignments.get(b, {}).get("score", 0.0)
		return score_a > score_b
	)

	for unit_id in assigned_units:
		var unit = snapshot.get("units", {}).get(unit_id, {})
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		var move_types = movable_units[unit_id]
		var assignment = assignments.get(unit_id, {})
		var assigned_obj_pos = assignment.get("objective_pos", Vector2.INF)
		var assigned_obj_id = assignment.get("objective_id", "")
		var assignment_action = assignment.get("action", "move")  # "hold", "move", "advance", "screen"

		# --- OC-AWARE HOLD DECISION ---
		if assignment_action == "hold":
			if "REMAIN_STATIONARY" in move_types:
				var dist_inches = assignment.get("distance", 0.0) / PIXELS_PER_INCH
				var reason = assignment.get("reason", "holding objective")
				print("AIDecisionMaker: %s holds %s (%s, %.1f\" away)" % [unit_name, assigned_obj_id, reason, dist_inches])
				return {
					"type": "REMAIN_STATIONARY",
					"actor_unit_id": unit_id,
					"_ai_description": "%s holds %s (%s)" % [unit_name, assigned_obj_id, reason]
				}

		# --- ADVANCE DECISION ---
		if assignment_action == "advance" and "BEGIN_ADVANCE" in move_types:
			var move_inches = float(unit.get("meta", {}).get("stats", {}).get("move", 6))
			var advance_move = move_inches + 2.0  # Average advance roll
			var target_pos = assigned_obj_pos if assigned_obj_pos != Vector2.INF else _nearest_objective_pos(_get_unit_centroid(unit), objectives)
			var model_destinations = _compute_movement_toward_target(
				unit, unit_id, target_pos, advance_move, snapshot, enemies
			)
			if not model_destinations.is_empty():
				var reason = assignment.get("reason", "needs extra distance")
				print("AIDecisionMaker: %s advances toward %s (%s)" % [unit_name, assigned_obj_id, reason])
				return {
					"type": "BEGIN_ADVANCE",
					"actor_unit_id": unit_id,
					"_ai_model_destinations": model_destinations,
					"_ai_description": "%s advances toward %s (%s)" % [unit_name, assigned_obj_id, reason]
				}

		# --- NORMAL MOVE toward assigned objective ---
		if "BEGIN_NORMAL_MOVE" in move_types:
			var move_inches = float(unit.get("meta", {}).get("stats", {}).get("move", 6))
			var centroid = _get_unit_centroid(unit)
			if centroid == Vector2.INF:
				continue
			var target_pos = assigned_obj_pos if assigned_obj_pos != Vector2.INF else _nearest_objective_pos(centroid, objectives)

			# If we're already within control range and assigned to hold, remain stationary
			if target_pos != Vector2.INF and centroid.distance_to(target_pos) <= OBJECTIVE_CONTROL_RANGE_PX:
				if "REMAIN_STATIONARY" in move_types:
					var dist_inches = centroid.distance_to(target_pos) / PIXELS_PER_INCH
					print("AIDecisionMaker: %s within control range of %s (%.1f\"), holding" % [unit_name, assigned_obj_id, dist_inches])
					return {
						"type": "REMAIN_STATIONARY",
						"actor_unit_id": unit_id,
						"_ai_description": "%s holds %s (%.1f\" away)" % [unit_name, assigned_obj_id, dist_inches]
					}

			var model_destinations = _compute_movement_toward_target(
				unit, unit_id, target_pos, move_inches, snapshot, enemies
			)

			if not model_destinations.is_empty():
				var obj_dist_inches = centroid.distance_to(target_pos) / PIXELS_PER_INCH if target_pos != Vector2.INF else 0.0
				var reason = assignment.get("reason", "moving to objective")
				print("AIDecisionMaker: %s moving toward %s (%s, M: %.0f\")" % [unit_name, assigned_obj_id, reason, move_inches])
				return {
					"type": "BEGIN_NORMAL_MOVE",
					"actor_unit_id": unit_id,
					"_ai_model_destinations": model_destinations,
					"_ai_description": "%s moves toward %s (%s, obj: %.1f\" away)" % [unit_name, assigned_obj_id, reason, obj_dist_inches]
				}
			else:
				print("AIDecisionMaker: %s cannot find valid move toward %s" % [unit_name, assigned_obj_id])

		# --- Fallback: remain stationary ---
		if "REMAIN_STATIONARY" in move_types:
			var reason = assignment.get("reason", "no valid move found")
			return {
				"type": "REMAIN_STATIONARY",
				"actor_unit_id": unit_id,
				"_ai_description": "%s remains stationary (%s)" % [unit_name, reason]
			}

	return {"type": "END_MOVEMENT", "_ai_description": "End Movement Phase"}

# =============================================================================
# OBJECTIVE EVALUATION (Task 1 + Task 5)
# =============================================================================

static func _evaluate_all_objectives(
	snapshot: Dictionary, objectives: Array, player: int,
	enemies: Dictionary, friendly_units: Dictionary, battle_round: int
) -> Array:
	# Returns array of objective evaluations with priority scores
	var evaluations = []
	var obj_data = snapshot.get("board", {}).get("objectives", [])

	for i in range(objectives.size()):
		var obj_pos = objectives[i]
		var obj_id = ""
		var obj_zone = "no_mans_land"
		if i < obj_data.size():
			obj_id = obj_data[i].get("id", "obj_%d" % i)
			obj_zone = obj_data[i].get("zone", "no_mans_land")

		# Calculate OC totals within control range
		var friendly_oc = _get_oc_at_position(obj_pos, friendly_units, player, true)
		var enemy_oc = _get_oc_at_position(obj_pos, enemies, player, false)

		# Count friendly/enemy units nearby (within 12")
		var friendly_nearby = _count_units_near_position(obj_pos, friendly_units, CHARGE_RANGE_PX)
		var enemy_nearby = _count_units_near_position(obj_pos, enemies, CHARGE_RANGE_PX)

		# Classify the objective state
		var state = "uncontrolled"
		if friendly_oc > 0 and friendly_oc > enemy_oc:
			if enemy_nearby > 0:
				state = "held_threatened"
			else:
				state = "held_safe"
		elif enemy_oc > 0 and enemy_oc > friendly_oc:
			if enemy_oc <= 4:  # Reasonable to contest
				state = "enemy_weak"
			else:
				state = "enemy_strong"
		elif friendly_oc > 0 and enemy_oc > 0:
			state = "contested"
		else:
			state = "uncontrolled"

		# Is this our home objective?
		var is_home = (player == 1 and obj_zone == "player1") or (player == 2 and obj_zone == "player2")
		var is_enemy_home = (player == 1 and obj_zone == "player2") or (player == 2 and obj_zone == "player1")

		# Calculate priority score
		var priority = 0.0
		match state:
			"uncontrolled":
				priority += WEIGHT_UNCONTROLLED_OBJ
			"contested":
				priority += WEIGHT_CONTESTED_OBJ
			"enemy_weak":
				priority += WEIGHT_ENEMY_WEAK_OBJ
			"enemy_strong":
				priority += WEIGHT_ENEMY_STRONG_OBJ
			"held_safe":
				priority += WEIGHT_ALREADY_HELD_OBJ
			"held_threatened":
				priority += WEIGHT_CONTESTED_OBJ * 0.8  # Still important to reinforce

		# Home objective bonus - defend it if undefended
		if is_home and friendly_oc == 0:
			priority += WEIGHT_HOME_UNDEFENDED

		# Scoring urgency: higher priority in Round 1 (need to be on objectives by Round 2)
		if battle_round == 1:
			priority += WEIGHT_SCORING_URGENCY
		elif battle_round >= 4:
			# Late game: every VP matters, prioritize flipping contested objectives
			if state in ["contested", "enemy_weak"]:
				priority += WEIGHT_SCORING_URGENCY * 0.5

		# Don't over-prioritize enemy home objectives (far away, hard to hold)
		if is_enemy_home and state == "enemy_strong":
			priority -= 3.0

		print("AIDecisionMaker: Objective %s: state=%s, friendly_oc=%d, enemy_oc=%d, priority=%.1f" % [obj_id, state, friendly_oc, enemy_oc, priority])

		evaluations.append({
			"index": i,
			"id": obj_id,
			"position": obj_pos,
			"zone": obj_zone,
			"state": state,
			"friendly_oc": friendly_oc,
			"enemy_oc": enemy_oc,
			"friendly_nearby": friendly_nearby,
			"enemy_nearby": enemy_nearby,
			"is_home": is_home,
			"is_enemy_home": is_enemy_home,
			"priority": priority,
			"oc_needed": max(0, enemy_oc - friendly_oc + 1)  # OC we need to add to flip control
		})

	return evaluations

# =============================================================================
# UNIT-TO-OBJECTIVE ASSIGNMENT (Task 1 + Task 2 + Task 3 + Task 6)
# =============================================================================

static func _assign_units_to_objectives(
	snapshot: Dictionary, movable_units: Dictionary, obj_evaluations: Array,
	objectives: Array, enemies: Dictionary, friendly_units: Dictionary,
	player: int, battle_round: int
) -> Dictionary:
	# Returns: {unit_id: {objective_id, objective_pos, action, score, reason, distance}}
	# Uses a greedy assignment algorithm: score all (unit, objective) pairs, assign best first

	var assignments = {}  # unit_id -> assignment dict
	var obj_oc_remaining = {}  # objective_id -> how much more OC is still needed there

	# Initialize OC needs per objective
	for eval in obj_evaluations:
		var obj_id = eval.id
		if eval.state in ["held_safe"]:
			obj_oc_remaining[obj_id] = 0  # Already fully held
		elif eval.state == "held_threatened":
			obj_oc_remaining[obj_id] = max(1, eval.enemy_oc)  # Might need reinforcement
		else:
			# Need enough OC to control: enemy_oc + 1 (minus what we already have)
			obj_oc_remaining[obj_id] = max(1, eval.oc_needed)

	# Build all (unit, objective) candidate pairs with scores
	var candidates = []
	for unit_id in movable_units:
		var unit = snapshot.get("units", {}).get(unit_id, {})
		var centroid = _get_unit_centroid(unit)
		if centroid == Vector2.INF:
			continue
		var move_types = movable_units[unit_id]
		var is_engaged = "BEGIN_FALL_BACK" in move_types and not "BEGIN_NORMAL_MOVE" in move_types
		if is_engaged:
			continue  # Engaged units handled separately

		var unit_oc = int(unit.get("meta", {}).get("stats", {}).get("objective_control", 1))
		var move_inches = float(unit.get("meta", {}).get("stats", {}).get("move", 6))
		var unit_keywords = unit.get("meta", {}).get("keywords", [])
		var has_ranged = _unit_has_ranged_weapons(unit)
		var max_weapon_range = _get_max_weapon_range(unit)

		for eval in obj_evaluations:
			var obj_pos = eval.position
			var obj_id = eval.id
			var dist_px = centroid.distance_to(obj_pos)
			var dist_inches = dist_px / PIXELS_PER_INCH
			var turns_to_reach = max(1.0, ceil(dist_inches / move_inches)) if move_inches > 0 else 99.0
			var already_on_obj = dist_px <= OBJECTIVE_CONTROL_RANGE_PX

			# Base score from objective priority
			var score = eval.priority

			# OC efficiency: high-OC units are more valuable at contested objectives
			if eval.oc_needed > 0:
				score += min(float(unit_oc) / max(1.0, float(eval.oc_needed)), 1.5) * WEIGHT_OC_EFFICIENCY

			# Distance penalty: further away = less useful
			if turns_to_reach > 1:
				score -= (turns_to_reach - 1) * 2.0

			# Already on the objective: big bonus for holding
			if already_on_obj:
				score += 5.0

			# Can reach this turn: bonus
			if dist_inches <= move_inches:
				score += 3.0
			elif dist_inches <= move_inches + 2.0:  # Reachable with advance
				score += 1.5

			# Scoring round awareness: if this is round 1 and we can't reach by round 2, lower priority
			if battle_round == 1 and turns_to_reach > 1:
				score -= 2.0

			# Unit suitability: units with shooting should consider range to enemies
			if has_ranged and eval.enemy_nearby > 0:
				score += 1.0  # Shooting units valuable where enemies are

			# Determine recommended action
			var action = "move"
			var reason = "moving to objective"

			if already_on_obj:
				action = "hold"
				reason = "on objective, OC needed"
			elif dist_inches > move_inches and dist_inches <= move_inches + 2.0:
				# Advance consideration (Task 3)
				var should_advance = _should_unit_advance(
					unit, dist_inches, move_inches, has_ranged, max_weapon_range,
					enemies, centroid, battle_round, eval
				)
				if should_advance:
					action = "advance"
					reason = "advancing for extra range"

			candidates.append({
				"unit_id": unit_id,
				"objective_id": obj_id,
				"objective_pos": obj_pos,
				"score": score,
				"action": action,
				"reason": reason,
				"distance": dist_px,
				"unit_oc": unit_oc,
				"already_on_obj": already_on_obj,
				"turns_to_reach": turns_to_reach
			})

	# Sort by score (highest first)
	candidates.sort_custom(func(a, b): return a.score > b.score)

	# Greedy assignment: assign the best (unit, objective) pair, then reduce OC need
	var assigned_unit_ids = {}  # Track which units are already assigned

	# PASS 1: Assign units already on objectives first (hold decisions)
	# Count how many movable units are on each objective
	var units_on_obj = {}  # obj_id -> count of movable units on it
	for cand in candidates:
		if cand.already_on_obj:
			units_on_obj[cand.objective_id] = units_on_obj.get(cand.objective_id, 0) + 1

	for cand in candidates:
		var uid = cand.unit_id
		var oid = cand.objective_id
		if assigned_unit_ids.has(uid):
			continue
		if not cand.already_on_obj:
			continue

		var remaining = obj_oc_remaining.get(oid, 0)
		var eval_for_obj = _get_obj_eval_by_id(obj_evaluations, oid)
		var obj_state = eval_for_obj.get("state", "")

		# Determine if this unit should hold here
		var should_hold = false
		if remaining > 0:
			should_hold = true  # OC still needed at this objective
		elif obj_state == "held_threatened":
			should_hold = true  # Threatened, keep defender
		elif units_on_obj.get(oid, 0) <= 1:
			# Only one unit on this objective — always hold to maintain control
			# Don't abandon a controlled objective
			should_hold = true
		# If multiple units on same held_safe objective, let extras move elsewhere

		if should_hold:
			assignments[uid] = cand
			assignments[uid]["action"] = "hold"
			assignments[uid]["reason"] = "holding objective (OC: %d)" % cand.unit_oc
			assigned_unit_ids[uid] = true
			obj_oc_remaining[oid] = max(0, remaining - cand.unit_oc)
			# Decrease count so second unit on same obj can be freed
			units_on_obj[oid] = units_on_obj.get(oid, 1) - 1
			print("AIDecisionMaker: Assigned %s to HOLD %s (OC: %d, remaining need: %d)" % [uid, oid, cand.unit_oc, obj_oc_remaining[oid]])
		else:
			# Objective already fully held by another unit — this unit should move elsewhere
			# Will be assigned in pass 2
			pass

	# PASS 2: Assign remaining units to objectives that still need OC
	for cand in candidates:
		var uid = cand.unit_id
		var oid = cand.objective_id
		if assigned_unit_ids.has(uid):
			continue

		var remaining = obj_oc_remaining.get(oid, 0)
		if remaining <= 0:
			# Check if any other objective still needs units
			var any_need = false
			for other_oid in obj_oc_remaining:
				if obj_oc_remaining[other_oid] > 0:
					any_need = true
					break
			if not any_need:
				# All objectives satisfied — assign to screen or best available
				pass  # Fall through to pass 3

			continue  # Skip objectives that don't need more OC

		assignments[uid] = cand
		assigned_unit_ids[uid] = true
		obj_oc_remaining[oid] = max(0, remaining - cand.unit_oc)
		print("AIDecisionMaker: Assigned %s to %s %s (score: %.1f, reason: %s)" % [uid, cand.action.to_upper(), oid, cand.score, cand.reason])

	# PASS 3: Assign any remaining unassigned units
	for unit_id in movable_units:
		if assigned_unit_ids.has(unit_id):
			continue
		var move_types = movable_units[unit_id]
		var is_engaged = "BEGIN_FALL_BACK" in move_types and not "BEGIN_NORMAL_MOVE" in move_types
		if is_engaged:
			continue

		var unit = snapshot.get("units", {}).get(unit_id, {})
		var centroid = _get_unit_centroid(unit)
		if centroid == Vector2.INF:
			continue

		# Find best objective for screening/support or just nearest useful one
		var best_obj = _find_best_remaining_objective(centroid, obj_evaluations, enemies, unit, snapshot, player)
		if not best_obj.is_empty():
			assignments[unit_id] = best_obj
			assigned_unit_ids[unit_id] = true
			print("AIDecisionMaker: Assigned %s to %s %s (support/screen)" % [unit_id, best_obj.action.to_upper(), best_obj.objective_id])
		else:
			# Truly nothing useful — remain stationary
			assignments[unit_id] = {
				"objective_id": "none",
				"objective_pos": Vector2.INF,
				"action": "hold",
				"score": -100.0,
				"reason": "no useful objective",
				"distance": 0.0
			}

	return assignments

# =============================================================================
# ENGAGED UNIT DECISION (Task 4: Smart Fall Back)
# =============================================================================

static func _decide_engaged_unit(
	unit: Dictionary, unit_id: String, unit_name: String,
	move_types: Array, objectives: Array, enemies: Dictionary,
	snapshot: Dictionary, player: int
) -> Dictionary:
	var centroid = _get_unit_centroid(unit)
	if centroid == Vector2.INF:
		if "REMAIN_STATIONARY" in move_types:
			return {"type": "REMAIN_STATIONARY", "actor_unit_id": unit_id, "_ai_description": "%s remains stationary (no position)" % unit_name}
		return {}

	# Check if this unit is on an objective
	var on_objective = false
	var obj_id_held = ""
	for obj_pos in objectives:
		if centroid.distance_to(obj_pos) <= OBJECTIVE_CONTROL_RANGE_PX:
			on_objective = true
			# Find the objective ID
			var obj_data = snapshot.get("board", {}).get("objectives", [])
			for od in obj_data:
				var op = od.get("position", null)
				if op != null:
					var opv = op if op is Vector2 else Vector2(float(op.get("x", 0)), float(op.get("y", 0)))
					if opv.distance_to(obj_pos) < 10.0:
						obj_id_held = od.get("id", "")
			break

	var unit_oc = int(unit.get("meta", {}).get("stats", {}).get("objective_control", 1))
	var friendly_units = _get_units_for_player(snapshot, player)

	if on_objective:
		# Check if our OC at this objective would be reduced by falling back
		var friendly_oc_here = _get_oc_at_position(
			centroid, friendly_units, player, true
		)
		var enemy_oc_here = _get_oc_at_position(
			centroid, enemies, player, false
		)

		# If we're winning the OC war or tied, stay and hold
		if friendly_oc_here >= enemy_oc_here and "REMAIN_STATIONARY" in move_types:
			print("AIDecisionMaker: %s engaged on %s but winning OC war (%d vs %d), holding" % [unit_name, obj_id_held, friendly_oc_here, enemy_oc_here])
			return {
				"type": "REMAIN_STATIONARY",
				"actor_unit_id": unit_id,
				"_ai_description": "%s holds %s while engaged (OC %d vs %d)" % [unit_name, obj_id_held, friendly_oc_here, enemy_oc_here]
			}

		# If we're losing OC but falling back would lose the objective entirely
		var oc_without_us = friendly_oc_here - unit_oc
		if oc_without_us <= 0 and "REMAIN_STATIONARY" in move_types:
			# We're the only one holding it — stay even if losing OC war
			print("AIDecisionMaker: %s engaged on %s, only holder (OC %d), staying" % [unit_name, obj_id_held, unit_oc])
			return {
				"type": "REMAIN_STATIONARY",
				"actor_unit_id": unit_id,
				"_ai_description": "%s stays on %s (only holder, OC: %d)" % [unit_name, obj_id_held, unit_oc]
			}

	# Not on objective or better to fall back — fall back
	if "BEGIN_FALL_BACK" in move_types:
		var reason = "not on objective" if not on_objective else "losing OC war"
		print("AIDecisionMaker: %s falling back (%s)" % [unit_name, reason])
		return {
			"type": "BEGIN_FALL_BACK",
			"actor_unit_id": unit_id,
			"_ai_description": "%s falls back (%s)" % [unit_name, reason]
		}

	if "REMAIN_STATIONARY" in move_types:
		return {
			"type": "REMAIN_STATIONARY",
			"actor_unit_id": unit_id,
			"_ai_description": "%s remains stationary (engaged, no fall back option)" % unit_name
		}

	return {}

# =============================================================================
# ADVANCE DECISION LOGIC (Task 3 + Task 6)
# =============================================================================

static func _should_unit_advance(
	unit: Dictionary, dist_inches: float, move_inches: float,
	has_ranged: bool, max_weapon_range: float, enemies: Dictionary,
	centroid: Vector2, battle_round: int, obj_eval: Dictionary
) -> bool:
	# Can't reach with normal move but can with advance?
	var can_reach_normal = dist_inches <= move_inches
	var can_reach_advance = dist_inches <= move_inches + 2.0  # Average advance

	if can_reach_normal:
		return false  # Normal move is enough

	if not can_reach_advance:
		return false  # Can't reach even with advance

	# Units without ranged weapons should always advance
	if not has_ranged:
		return true

	# Battle-shocked units can't shoot anyway — advance
	if unit.get("flags", {}).get("battle_shocked", false):
		return true

	# Round 1: aggressive positioning is critical for Round 2 scoring
	if battle_round == 1:
		# Advance to reach no-man's-land objectives
		if obj_eval.get("zone", "") == "no_mans_land":
			return true

	# High-priority uncontrolled objective: advancing to grab it is worth losing shooting
	if obj_eval.get("state", "") == "uncontrolled" and obj_eval.get("priority", 0) >= 8.0:
		return true

	# Cross-phase consideration (Task 6): check if we have viable shooting targets nearby
	var has_targets_in_range = false
	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		var enemy_centroid = _get_unit_centroid(enemy)
		if enemy_centroid == Vector2.INF:
			continue
		if centroid.distance_to(enemy_centroid) <= max_weapon_range * PIXELS_PER_INCH:
			has_targets_in_range = true
			break

	# If no targets in range anyway, advancing costs nothing
	if not has_targets_in_range:
		return true

	# Otherwise, prefer shooting over advancing
	return false

# =============================================================================
# MOVEMENT HELPERS (Enhanced)
# =============================================================================

static func _get_oc_at_position(pos: Vector2, units: Dictionary, player: int, is_friendly: bool) -> int:
	# Sum up OC values of all units within control range of a position
	var total_oc = 0
	for uid in units:
		var unit = units[uid]
		# Skip battle-shocked units (they have 0 effective OC)
		if unit.get("flags", {}).get("battle_shocked", false):
			continue
		var status = unit.get("status", 0)
		if status == GameStateData.UnitStatus.UNDEPLOYED or status == GameStateData.UnitStatus.IN_RESERVES:
			continue
		var oc_val = int(unit.get("meta", {}).get("stats", {}).get("objective_control", 0))
		if oc_val <= 0:
			continue
		# Check if any alive model is within control range
		for model in unit.get("models", []):
			if not model.get("alive", true):
				continue
			var mpos = _get_model_position(model)
			if mpos == Vector2.INF:
				continue
			if mpos.distance_to(pos) <= OBJECTIVE_CONTROL_RANGE_PX:
				total_oc += oc_val
				break  # Count unit once
	return total_oc

static func _count_units_near_position(pos: Vector2, units: Dictionary, range_px: float) -> int:
	var count = 0
	for uid in units:
		var unit = units[uid]
		var status = unit.get("status", 0)
		if status == GameStateData.UnitStatus.UNDEPLOYED or status == GameStateData.UnitStatus.IN_RESERVES:
			continue
		var centroid = _get_unit_centroid(unit)
		if centroid == Vector2.INF:
			continue
		if centroid.distance_to(pos) <= range_px:
			count += 1
	return count

static func _unit_has_ranged_weapons(unit: Dictionary) -> bool:
	var weapons = unit.get("meta", {}).get("weapons", [])
	for w in weapons:
		if w.get("type", "").to_lower() == "ranged":
			return true
	return false

static func _get_max_weapon_range(unit: Dictionary) -> float:
	var max_range = 0.0
	var weapons = unit.get("meta", {}).get("weapons", [])
	for w in weapons:
		if w.get("type", "").to_lower() == "ranged":
			var range_str = w.get("range", "0")
			if range_str.is_valid_float():
				max_range = max(max_range, float(range_str))
			elif range_str.is_valid_int():
				max_range = max(max_range, float(int(range_str)))
	return max_range

static func _nearest_objective_pos(pos: Vector2, objectives: Array) -> Vector2:
	var best = Vector2.INF
	var best_dist = INF
	for obj_pos in objectives:
		var d = pos.distance_to(obj_pos)
		if d < best_dist:
			best_dist = d
			best = obj_pos
	return best

static func _get_obj_eval_by_id(evaluations: Array, obj_id: String) -> Dictionary:
	for eval in evaluations:
		if eval.id == obj_id:
			return eval
	return {}

static func _find_best_remaining_objective(
	centroid: Vector2, obj_evaluations: Array, enemies: Dictionary,
	unit: Dictionary, snapshot: Dictionary, player: int
) -> Dictionary:
	# For unassigned units: find the best objective to support or screen near
	var best_score = -INF
	var best = {}
	var move_inches = float(unit.get("meta", {}).get("stats", {}).get("move", 6))
	var unit_oc = int(unit.get("meta", {}).get("stats", {}).get("objective_control", 1))
	var has_ranged = _unit_has_ranged_weapons(unit)

	for eval in obj_evaluations:
		var dist = centroid.distance_to(eval.position)
		var dist_inches = dist / PIXELS_PER_INCH

		# Score based on: priority + proximity + can we help?
		var score = eval.priority
		score -= dist_inches * 0.5  # Closer is better

		# Contested/threatened objectives benefit most from reinforcement
		if eval.state in ["contested", "held_threatened", "enemy_weak"]:
			score += 3.0

		# Screening position: place between enemy and valuable friendly-held objectives
		if eval.state == "held_safe" and eval.enemy_nearby > 0:
			score += 2.0  # Screen for held objectives

		# Shooting support: ranged units should move toward enemy-adjacent objectives
		if has_ranged and eval.enemy_nearby > 0:
			score += 1.5

		if score > best_score:
			best_score = score
			var action = "move"
			var reason = "supporting nearby objective"
			if dist <= OBJECTIVE_CONTROL_RANGE_PX:
				action = "hold"
				reason = "already at objective"
			best = {
				"objective_id": eval.id,
				"objective_pos": eval.position,
				"action": action,
				"score": score,
				"reason": reason,
				"distance": dist,
				"unit_oc": unit_oc
			}

	return best

static func _compute_movement_toward_target(
	unit: Dictionary, unit_id: String, target_pos: Vector2,
	move_inches: float, snapshot: Dictionary, enemies: Dictionary
) -> Dictionary:
	# Generalized version of _compute_movement_toward_objective that takes a specific target position
	if target_pos == Vector2.INF:
		return {}

	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return {}

	var centroid = _get_unit_centroid(unit)
	if centroid == Vector2.INF:
		return {}

	# Calculate movement vector toward target
	var direction = (target_pos - centroid).normalized()
	var move_px = move_inches * PIXELS_PER_INCH
	var dist_to_target = centroid.distance_to(target_pos)
	var actual_move_px = min(move_px, dist_to_target)
	var move_vector = direction * actual_move_px

	# Get terrain features for blocking checks
	var terrain_features = snapshot.get("board", {}).get("terrain_features", [])
	var unit_keywords = unit.get("meta", {}).get("keywords", [])

	# Check if the direct path is blocked by terrain (Task 8: terrain-aware pathing)
	var final_move_vector = _find_unblocked_move_enhanced(
		centroid, move_vector, actual_move_px, unit_keywords, terrain_features, enemies, unit
	)

	if final_move_vector == Vector2.ZERO:
		print("AIDecisionMaker: All movement paths blocked by terrain")
		return {}

	# Get all deployed model positions (excluding this unit's own models) for overlap checking
	var deployed_models = _get_deployed_models_excluding_unit(snapshot, unit_id)
	var first_model = alive_models[0] if alive_models.size() > 0 else {}
	var base_mm = first_model.get("base_mm", 32)
	var base_type = first_model.get("base_type", "circular")
	var base_dimensions = first_model.get("base_dimensions", {})

	# Build original positions map for movement cap checking during collision resolution
	var original_positions = {}
	for model in alive_models:
		var mid = model.get("id", "")
		if mid != "":
			original_positions[mid] = _get_model_position(model)

	# Try the full move first, then progressively shorter moves
	var fractions_to_try = [1.0, 0.75, 0.5, 0.25]
	for fraction in fractions_to_try:
		var try_vector = final_move_vector * fraction
		var destinations = _try_move_with_collision_check(
			alive_models, try_vector, enemies, unit, deployed_models,
			base_mm, base_type, base_dimensions, original_positions, move_px
		)
		if not destinations.is_empty():
			if fraction < 1.0:
				print("AIDecisionMaker: Using %.0f%% move to avoid model overlap" % (fraction * 100))
			return destinations

	# All fractions failed
	return {}

static func _find_unblocked_move_enhanced(
	centroid: Vector2, move_vector: Vector2, move_distance_px: float,
	unit_keywords: Array, terrain_features: Array,
	enemies: Dictionary, unit: Dictionary
) -> Vector2:
	# Enhanced version with terrain-aware pathing (Task 8)
	# Try the direct path first
	if not _path_blocked_by_terrain(centroid, centroid + move_vector, unit_keywords, terrain_features):
		# Task 8: Check if a path through cover would be better
		var cover_path = _find_cover_path(centroid, move_vector, move_distance_px, unit_keywords, terrain_features, enemies)
		if cover_path != Vector2.ZERO:
			return cover_path
		return move_vector

	print("AIDecisionMaker: Direct path blocked, trying alternate directions")

	# Try angled alternatives: +/-30, +/-60, +/-90
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

# =============================================================================
# TERRAIN-AWARE PATHING (Task 8)
# =============================================================================

static func _find_cover_path(
	centroid: Vector2, move_vector: Vector2, move_distance_px: float,
	unit_keywords: Array, terrain_features: Array, enemies: Dictionary
) -> Vector2:
	# Check if there's a safer path that ends in/near cover from enemy LoS
	# Only redirect if enemies are nearby and cover is available along the route
	var dest = centroid + move_vector

	# Find nearby enemy positions
	var enemy_positions = []
	for eid in enemies:
		var enemy = enemies[eid]
		var ecentroid = _get_unit_centroid(enemy)
		if ecentroid != Vector2.INF:
			enemy_positions.append(ecentroid)

	if enemy_positions.is_empty():
		return Vector2.ZERO  # No enemies to hide from, use direct path

	# Check if the direct destination has terrain cover from enemies
	var direct_has_cover = _position_has_cover(dest, enemy_positions, terrain_features)
	if direct_has_cover:
		return Vector2.ZERO  # Direct path already ends in cover

	# Try slight adjustments (+/-15, +/-30 degrees) to find a covered endpoint
	var base_dir = move_vector.normalized()
	var small_angles = [deg_to_rad(15), deg_to_rad(-15), deg_to_rad(30), deg_to_rad(-30)]

	for angle in small_angles:
		var alt_dir = base_dir.rotated(angle)
		var alt_vector = alt_dir * move_distance_px
		var alt_dest = centroid + alt_vector
		if not _path_blocked_by_terrain(centroid, alt_dest, unit_keywords, terrain_features):
			if _position_has_cover(alt_dest, enemy_positions, terrain_features):
				print("AIDecisionMaker: Found cover path at %.0f degrees offset" % rad_to_deg(angle))
				return alt_vector

	return Vector2.ZERO  # No better cover path found

static func _position_has_cover(pos: Vector2, enemy_positions: Array, terrain_features: Array) -> bool:
	# Check if a position has terrain between it and enemy positions (providing cover/LoS blocking)
	for enemy_pos in enemy_positions:
		for terrain in terrain_features:
			var polygon = terrain.get("polygon", [])
			var packed = PackedVector2Array()
			if polygon is PackedVector2Array:
				packed = polygon
			elif polygon is Array and polygon.size() >= 3:
				for p in polygon:
					if p is Vector2:
						packed.append(p)
					elif p is Dictionary:
						packed.append(Vector2(float(p.get("x", 0)), float(p.get("y", 0))))

			if packed.size() >= 3:
				# Check if terrain blocks LoS from enemy to this position
				if _line_intersects_polygon(enemy_pos, pos, packed):
					return true  # At least one enemy has LoS blocked by terrain
	return false

# =============================================================================
# SCREENING/DEFENSIVE POSITIONING (Task 7)
# =============================================================================

static func _compute_screen_position(
	unit: Dictionary, unit_id: String, friendly_units: Dictionary,
	enemies: Dictionary, snapshot: Dictionary
) -> Vector2:
	# Find a good screening position between enemies and valuable friendly units
	var centroid = _get_unit_centroid(unit)
	if centroid == Vector2.INF:
		return Vector2.INF

	# Find the nearest enemy threat
	var nearest_enemy_pos = Vector2.INF
	var nearest_enemy_dist = INF
	for eid in enemies:
		var enemy = enemies[eid]
		var ecentroid = _get_unit_centroid(enemy)
		if ecentroid == Vector2.INF:
			continue
		var d = centroid.distance_to(ecentroid)
		if d < nearest_enemy_dist:
			nearest_enemy_dist = d
			nearest_enemy_pos = ecentroid

	if nearest_enemy_pos == Vector2.INF:
		return Vector2.INF

	# Find the nearest valuable friendly unit to protect
	var protect_pos = Vector2.INF
	var protect_dist = INF
	for fid in friendly_units:
		if fid == unit_id:
			continue
		var funit = friendly_units[fid]
		var fcentroid = _get_unit_centroid(funit)
		if fcentroid == Vector2.INF:
			continue
		# Prioritize protecting units near objectives or with high value
		var d = centroid.distance_to(fcentroid)
		if d < protect_dist:
			protect_dist = d
			protect_pos = fcentroid

	if protect_pos == Vector2.INF:
		return Vector2.INF

	# Screen position: halfway between the friendly unit and the enemy, leaning toward enemy
	var screen_pos = protect_pos + (nearest_enemy_pos - protect_pos) * 0.6
	return screen_pos

# --- Movement helpers ---

static func _nearest_objective_distance(pos: Vector2, objectives: Array) -> float:
	var best = INF
	for obj_pos in objectives:
		var d = pos.distance_to(obj_pos)
		if d < best:
			best = d
	return best

# _compute_movement_toward_objective: REMOVED - replaced by _compute_movement_toward_target
# _find_unblocked_move: REMOVED - replaced by _find_unblocked_move_enhanced

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

# _try_shorter_move: REMOVED - functionality integrated into _try_move_with_collision_check

static func _try_move_with_collision_check(
	alive_models: Array, move_vector: Vector2, enemies: Dictionary,
	unit: Dictionary, deployed_models: Array, base_mm: int,
	base_type: String, base_dimensions: Dictionary,
	original_positions: Dictionary = {}, move_cap_px: float = 0.0
) -> Dictionary:
	# Try moving all models by move_vector, checking both enemy ER and model overlap
	var destinations = {}
	# Track models we've placed in this move for intra-unit collision
	var placed_models: Array = []

	for model in alive_models:
		var model_id = model.get("id", "")
		if model_id == "":
			continue
		var model_pos = _get_model_position(model)
		if model_pos == Vector2.INF:
			continue
		var dest = model_pos + move_vector

		# Clamp to board bounds with margin
		dest.x = clamp(dest.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		dest.y = clamp(dest.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

		# Check enemy engagement range
		if _is_position_near_enemy(dest, enemies, unit):
			return {}

		# Check overlap with deployed models and already-placed models in this move
		var all_obstacles = deployed_models + placed_models
		if _position_collides_with_deployed(dest, base_mm, all_obstacles, 4.0, base_type, base_dimensions):
			# Try small perpendicular offsets to avoid the collision
			var orig_pos = original_positions.get(model_id, model_pos)
			var resolved_dest = _resolve_movement_collision(
				dest, move_vector, base_mm, base_type, base_dimensions,
				all_obstacles, enemies, unit, orig_pos, move_cap_px
			)
			if resolved_dest == Vector2.INF:
				return {}  # Could not resolve collision
			dest = resolved_dest

		destinations[model_id] = [dest.x, dest.y]
		placed_models.append({
			"position": dest,
			"base_mm": base_mm,
			"base_type": base_type,
			"base_dimensions": base_dimensions
		})

	return destinations

static func _resolve_movement_collision(
	dest: Vector2, move_vector: Vector2, base_mm: int,
	base_type: String, base_dimensions: Dictionary,
	obstacles: Array, enemies: Dictionary, unit: Dictionary,
	original_pos: Vector2 = Vector2.INF, move_cap_px: float = 0.0
) -> Vector2:
	# Try perpendicular offsets to avoid collision while staying close to intended destination
	var perp = Vector2(-move_vector.y, move_vector.x).normalized()
	var base_radius = _model_bounding_radius_px(base_mm, base_type, base_dimensions)
	var offsets = [1.0, -1.0, 2.0, -2.0, 3.0, -3.0]

	for multiplier in offsets:
		var offset = perp * base_radius * multiplier
		var candidate = dest + offset

		# Check board bounds
		if candidate.x < BASE_MARGIN_PX or candidate.x > BOARD_WIDTH_PX - BASE_MARGIN_PX:
			continue
		if candidate.y < BASE_MARGIN_PX or candidate.y > BOARD_HEIGHT_PX - BASE_MARGIN_PX:
			continue

		# Check movement cap: offset must not push model beyond its movement distance
		if original_pos != Vector2.INF and move_cap_px > 0.0:
			var offset_dist = original_pos.distance_to(candidate)
			if offset_dist > move_cap_px:
				continue

		if not _position_collides_with_deployed(candidate, base_mm, obstacles, 4.0, base_type, base_dimensions):
			if not _is_position_near_enemy(candidate, enemies, unit):
				return candidate

	return Vector2.INF  # No valid offset found

static func _get_deployed_models_excluding_unit(snapshot: Dictionary, exclude_unit_id: String) -> Array:
	# Returns model positions for all on-board units except the specified one
	# Includes DEPLOYED, MOVED, SHOT, CHARGED statuses (any unit physically on the board)
	var deployed = []
	for uid in snapshot.get("units", {}):
		if uid == exclude_unit_id:
			continue
		var u = snapshot.units[uid]
		var status = u.get("status", 0)
		if status == GameStateData.UnitStatus.UNDEPLOYED or status == GameStateData.UnitStatus.IN_RESERVES:
			continue
		for model in u.get("models", []):
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

	# Step 0: Complete shooting for unit if needed (safety net)
	if action_types.has("COMPLETE_SHOOTING_FOR_UNIT"):
		var a = action_types["COMPLETE_SHOOTING_FOR_UNIT"][0]
		return {
			"type": "COMPLETE_SHOOTING_FOR_UNIT",
			"actor_unit_id": a.get("actor_unit_id", ""),
			"_ai_description": "Complete shooting for unit"
		}

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
			var weapon_id = _generate_weapon_id(weapon_name, weapon.get("type", ""))

			# ONE SHOT (T4-2): Skip one-shot weapons that have been fired
			if RulesEngine.is_one_shot_weapon(weapon_id, snapshot):
				var all_fired = true
				var models = unit.get("models", [])
				for model in models:
					if model.get("alive", true):
						var model_id = model.get("id", "")
						if not RulesEngine.has_fired_one_shot(unit, model_id, weapon_id):
							all_fired = false
							break
				if all_fired:
					continue

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

	# --- Step 0: Handle reaction decisions first ---

	# Command Re-roll: always decline for now (stratagem usage is a separate task)
	if action_types.has("DECLINE_COMMAND_REROLL"):
		return {
			"type": "DECLINE_COMMAND_REROLL",
			"_ai_description": "Decline Command Re-roll (charge)"
		}

	# Fire Overwatch: always decline for now (stratagem usage is a separate task)
	if action_types.has("DECLINE_FIRE_OVERWATCH"):
		return {
			"type": "DECLINE_FIRE_OVERWATCH",
			"_ai_description": "Decline Fire Overwatch"
		}

	# Heroic Intervention: always decline for now (stratagem usage is a separate task)
	if action_types.has("DECLINE_HEROIC_INTERVENTION"):
		return {
			"type": "DECLINE_HEROIC_INTERVENTION",
			"_ai_description": "Decline Heroic Intervention"
		}

	# Tank Shock: always decline for now (stratagem usage is a separate task)
	if action_types.has("DECLINE_TANK_SHOCK"):
		return {
			"type": "DECLINE_TANK_SHOCK",
			"_ai_description": "Decline Tank Shock"
		}

	# --- Step 1: Complete any pending charge ---
	if action_types.has("COMPLETE_UNIT_CHARGE"):
		var a = action_types["COMPLETE_UNIT_CHARGE"][0]
		var uid = a.get("actor_unit_id", "")
		var unit = snapshot.get("units", {}).get(uid, {})
		var unit_name = unit.get("meta", {}).get("name", uid)
		return {
			"type": "COMPLETE_UNIT_CHARGE",
			"actor_unit_id": uid,
			"_ai_description": "Complete charge for %s" % unit_name
		}

	# --- Step 2: Apply charge movement if a roll was successful ---
	if action_types.has("APPLY_CHARGE_MOVE"):
		var a = action_types["APPLY_CHARGE_MOVE"][0]
		var uid = a.get("actor_unit_id", "")
		var rolled_distance = a.get("rolled_distance", 0)
		var target_ids = a.get("target_ids", [])
		return _compute_charge_move(snapshot, uid, rolled_distance, target_ids, player)

	# --- Step 3: If charge roll is needed, roll ---
	if action_types.has("CHARGE_ROLL"):
		var a = action_types["CHARGE_ROLL"][0]
		var uid = a.get("actor_unit_id", "")
		var unit = snapshot.get("units", {}).get(uid, {})
		var unit_name = unit.get("meta", {}).get("name", uid)
		return {
			"type": "CHARGE_ROLL",
			"actor_unit_id": uid,
			"_ai_description": "Charge roll for %s" % unit_name
		}

	# --- Step 4: Evaluate and declare charges ---
	if action_types.has("DECLARE_CHARGE"):
		var best_charge = _evaluate_best_charge(snapshot, available_actions, player)
		if not best_charge.is_empty():
			return best_charge

		# No good charge found — skip remaining chargeable units one at a time
		if action_types.has("SKIP_CHARGE"):
			var a = action_types["SKIP_CHARGE"][0]
			var uid = a.get("actor_unit_id", "")
			var unit = snapshot.get("units", {}).get(uid, {})
			var unit_name = unit.get("meta", {}).get("name", uid)
			return {
				"type": "SKIP_CHARGE",
				"actor_unit_id": uid,
				"_ai_description": "Skipped charge for %s (no good target)" % unit_name
			}

	# --- Step 5: End charge phase ---
	return {"type": "END_CHARGE", "_ai_description": "End Charge Phase"}

# =============================================================================
# CHARGE EVALUATION
# =============================================================================

static func _evaluate_best_charge(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	"""Evaluate all possible charge declarations and return the best one, or {} if none worth taking."""
	var enemies = _get_enemy_units(snapshot, player)

	# Collect unique charger unit IDs from DECLARE_CHARGE actions
	var charger_targets = {}  # unit_id -> [{target_id, distance_inches, action}]
	for a in available_actions:
		if a.get("type") != "DECLARE_CHARGE":
			continue
		var uid = a.get("actor_unit_id", "")
		var target_ids = a.get("payload", {}).get("target_unit_ids", [])
		if uid == "" or target_ids.is_empty():
			continue

		if not charger_targets.has(uid):
			charger_targets[uid] = []

		var target_id = target_ids[0]
		var unit = snapshot.get("units", {}).get(uid, {})
		var target_unit = snapshot.get("units", {}).get(target_id, {})
		if unit.is_empty() or target_unit.is_empty():
			continue

		# Calculate closest model distance to target
		var min_dist = _get_closest_model_distance_inches(unit, target_unit)

		charger_targets[uid].append({
			"target_id": target_id,
			"distance_inches": min_dist,
			"action": a,
		})

	if charger_targets.is_empty():
		return {}

	# Score each (charger, target) pair
	var best_score = -INF
	var best_action = {}
	var best_description = ""

	for uid in charger_targets:
		var unit = snapshot.get("units", {}).get(uid, {})
		var unit_name = unit.get("meta", {}).get("name", uid)
		var unit_keywords = unit.get("meta", {}).get("keywords", [])
		var has_melee = _unit_has_melee_weapons(unit)

		# Units without melee weapons should generally not charge (except for objective play)
		var melee_bonus = 1.0 if has_melee else 0.3

		for target_info in charger_targets[uid]:
			var target_id = target_info.target_id
			var dist = target_info.distance_inches
			var target_unit = enemies.get(target_id, {})
			if target_unit.is_empty():
				continue
			var target_name = target_unit.get("meta", {}).get("name", target_id)

			# Calculate charge probability (2D6 must meet or exceed distance - ER)
			var charge_distance_needed = max(0.0, dist - 1.0)  # minus 1" engagement range
			var charge_prob = _charge_success_probability(charge_distance_needed)

			# Skip charges with very low probability
			if charge_prob < 0.08:  # Less than ~8% chance (need 11+ on 2d6)
				print("AIDecisionMaker: Skipping charge %s -> %s (prob=%.1f%%, need=%.1f\")" % [
					unit_name, target_name, charge_prob * 100.0, charge_distance_needed])
				continue

			# Score the charge target
			var target_score = _score_charge_target(unit, target_unit, snapshot, player)

			# Apply charge probability as a multiplier
			var score = target_score * charge_prob * melee_bonus

			# Bonus for short charges (high reliability)
			if charge_distance_needed <= 6.0:
				score *= 1.2
			if charge_distance_needed <= 3.0:
				score *= 1.3

			# Bonus for charging onto objectives
			var target_centroid = _get_unit_centroid(target_unit)
			var objectives = _get_objectives(snapshot)
			for obj_pos in objectives:
				if target_centroid != Vector2.INF and target_centroid.distance_to(obj_pos) <= OBJECTIVE_CONTROL_RANGE_PX:
					score *= 1.5  # Target is on an objective
					break

			print("AIDecisionMaker: Charge eval %s -> %s: dist=%.1f\", prob=%.0f%%, target_score=%.1f, final=%.1f" % [
				unit_name, target_name, dist, charge_prob * 100.0, target_score, score])

			if score > best_score:
				best_score = score
				best_action = target_info.action
				best_description = "%s declares charge against %s (%.0f%% chance, %.1f\" away)" % [
					unit_name, target_name, charge_prob * 100.0, dist]

	# Minimum threshold to declare a charge
	if best_score < 1.0:
		print("AIDecisionMaker: No charge worth declaring (best score: %.1f)" % best_score)
		return {}

	print("AIDecisionMaker: Best charge: %s (score=%.1f)" % [best_description, best_score])
	var result = best_action.duplicate()
	result["_ai_description"] = best_description
	return result

static func _charge_success_probability(distance_needed: float) -> float:
	"""Calculate the probability that 2D6 >= distance_needed.
	Returns value between 0.0 and 1.0."""
	# 2D6 ranges from 2 to 12
	# We need the roll to be >= ceil(distance_needed)
	var needed = ceili(distance_needed)

	if needed <= 2:
		return 1.0  # Always succeeds (2D6 minimum is 2)
	if needed > 12:
		return 0.0  # Impossible

	# Count outcomes where sum >= needed out of 36 total outcomes
	var success_count = 0
	for d1 in range(1, 7):
		for d2 in range(1, 7):
			if d1 + d2 >= needed:
				success_count += 1

	return float(success_count) / 36.0

static func _score_charge_target(charger: Dictionary, target: Dictionary, snapshot: Dictionary, player: int) -> float:
	"""Score a potential charge target based on expected melee damage, target value, and tactical factors."""
	var score = 0.0

	# --- Expected melee damage ---
	var melee_damage = _estimate_melee_damage(charger, target)
	score += melee_damage * 2.0  # Weight melee damage highly

	# --- Target value factors ---
	var target_keywords = target.get("meta", {}).get("keywords", [])
	var target_wounds = int(target.get("meta", {}).get("stats", {}).get("wounds", 1))
	var alive_models = _get_alive_models(target).size()
	var total_models = target.get("models", []).size()

	# Bonus for targets below half strength (easier to finish off)
	if total_models > 0 and alive_models * 2 < total_models:
		score += 3.0

	# Bonus for CHARACTER targets
	if "CHARACTER" in target_keywords:
		score += 2.0

	# Penalty for very tough targets we can't damage effectively
	if melee_damage < 1.0:
		score -= 3.0

	# Bonus for engaging dangerous ranged units (stops them from shooting)
	var target_has_ranged = _unit_has_ranged_weapons(target)
	if target_has_ranged:
		var max_range = _get_max_weapon_range(target)
		if max_range >= 24.0:
			score += 2.0  # Good to tie up long-range shooters

	# Bonus for targeting units with low toughness (likely kill)
	var target_toughness = int(target.get("meta", {}).get("stats", {}).get("toughness", 4))
	if target_toughness <= 3:
		score += 1.0

	return max(0.0, score)

static func _estimate_melee_damage(attacker: Dictionary, defender: Dictionary) -> float:
	"""Estimate expected damage from a melee attack using the attacker's best melee weapon."""
	var weapons = attacker.get("meta", {}).get("weapons", [])
	var best_damage = 0.0
	var alive_attackers = _get_alive_models(attacker).size()

	var target_toughness = int(defender.get("meta", {}).get("stats", {}).get("toughness", 4))
	var target_save = int(defender.get("meta", {}).get("stats", {}).get("save", 4))

	for w in weapons:
		if w.get("type", "").to_lower() != "melee":
			continue

		var attacks_str = w.get("attacks", "1")
		var attacks = float(attacks_str) if attacks_str.is_valid_float() else 1.0

		var ws_str = w.get("weapon_skill", w.get("ballistic_skill", "4"))
		var ws = int(ws_str) if ws_str.is_valid_int() else 4

		var strength_str = w.get("strength", "4")
		var strength = int(strength_str) if strength_str.is_valid_int() else 4

		var ap_str = w.get("ap", "0")
		var ap = 0
		if ap_str.begins_with("-"):
			var ap_num = ap_str.substr(1)
			ap = int(ap_num) if ap_num.is_valid_int() else 0
		else:
			ap = int(ap_str) if ap_str.is_valid_int() else 0

		var damage_str = w.get("damage", "1")
		var damage = float(damage_str) if damage_str.is_valid_float() else 1.0

		var p_hit = _hit_probability(ws)
		var p_wound = _wound_probability(strength, target_toughness)
		var p_unsaved = 1.0 - _save_probability(target_save, ap)

		# Total expected damage for entire unit with this weapon
		var weapon_damage = attacks * alive_attackers * p_hit * p_wound * p_unsaved * damage
		best_damage = max(best_damage, weapon_damage)

	# Fallback: close combat weapon (S=user, AP0, D1, 1 attack)
	if best_damage == 0.0 and alive_attackers > 0:
		var charger_strength = int(attacker.get("meta", {}).get("stats", {}).get("toughness", 4))
		var p_hit = _hit_probability(4)  # WS4+ default
		var p_wound = _wound_probability(charger_strength, target_toughness)
		var p_unsaved = 1.0 - _save_probability(target_save, 0)
		best_damage = alive_attackers * p_hit * p_wound * p_unsaved * 1.0

	return best_damage

static func _unit_has_melee_weapons(unit: Dictionary) -> bool:
	"""Check if a unit has any melee weapons (besides default close combat weapon)."""
	var weapons = unit.get("meta", {}).get("weapons", [])
	for w in weapons:
		if w.get("type", "").to_lower() == "melee":
			return true
	return false

static func _get_closest_model_distance_inches(unit_a: Dictionary, unit_b: Dictionary) -> float:
	"""Get the minimum edge-to-edge distance in inches between any two models of two units.
	Uses pixel-based position calculation since Measurement autoload may not be available statically."""
	var min_dist_px = INF
	for model_a in unit_a.get("models", []):
		if not model_a.get("alive", true):
			continue
		var pos_a = _get_model_position(model_a)
		if pos_a == Vector2.INF:
			continue
		var base_a_mm = model_a.get("base_mm", 32)
		var base_a_radius_px = _model_bounding_radius_px(base_a_mm, model_a.get("base_type", "circular"), model_a.get("base_dimensions", {}))

		for model_b in unit_b.get("models", []):
			if not model_b.get("alive", true):
				continue
			var pos_b = _get_model_position(model_b)
			if pos_b == Vector2.INF:
				continue
			var base_b_mm = model_b.get("base_mm", 32)
			var base_b_radius_px = _model_bounding_radius_px(base_b_mm, model_b.get("base_type", "circular"), model_b.get("base_dimensions", {}))

			# Edge-to-edge distance in pixels
			var center_dist = pos_a.distance_to(pos_b)
			var edge_dist_px = center_dist - base_a_radius_px - base_b_radius_px
			min_dist_px = min(min_dist_px, edge_dist_px)

	if min_dist_px == INF:
		return INF
	return max(0.0, min_dist_px) / PIXELS_PER_INCH

# =============================================================================
# CHARGE MOVEMENT COMPUTATION
# =============================================================================

static func _compute_charge_move(snapshot: Dictionary, unit_id: String, rolled_distance: int, target_ids: Array, player: int) -> Dictionary:
	"""Compute model positions for a charge move. Each model must:
	1. Move at most rolled_distance inches
	2. End closer to at least one charge target than it started
	3. At least one model must end within engagement range (1") of each declared target
	4. No model may end within engagement range of a non-target enemy
	5. Unit coherency must be maintained
	6. No model overlaps
	Returns an APPLY_CHARGE_MOVE action dict with per_model_paths, or a SKIP_CHARGE fallback."""

	var unit = snapshot.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {"type": "SKIP_CHARGE", "actor_unit_id": unit_id, "_ai_description": "Skip charge (unit not found)"}

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return {"type": "SKIP_CHARGE", "actor_unit_id": unit_id, "_ai_description": "Skip charge for %s (no alive models)" % unit_name}

	# Gather target model positions (closest model per target)
	var target_positions = []  # Array of Vector2 (closest target model to charger centroid)
	var charger_centroid = _get_unit_centroid(unit)
	for target_id in target_ids:
		var target_unit = snapshot.get("units", {}).get(target_id, {})
		if target_unit.is_empty():
			continue
		var closest_pos = Vector2.INF
		var closest_dist = INF
		for tm in target_unit.get("models", []):
			if not tm.get("alive", true):
				continue
			var tp = _get_model_position(tm)
			if tp == Vector2.INF:
				continue
			var d = charger_centroid.distance_to(tp)
			if d < closest_dist:
				closest_dist = d
				closest_pos = tp
		if closest_pos != Vector2.INF:
			target_positions.append(closest_pos)

	if target_positions.is_empty():
		return {"type": "SKIP_CHARGE", "actor_unit_id": unit_id, "_ai_description": "Skip charge for %s (no target positions)" % unit_name}

	# Primary target: the first (typically only) target
	var primary_target_pos = target_positions[0]

	# Get all non-target enemy model positions to avoid ending in their engagement range
	var non_target_enemies = []  # Array of {position: Vector2, base_radius_px: float}
	for uid in snapshot.get("units", {}):
		var u = snapshot.units[uid]
		if u.get("owner", 0) == player:
			continue  # Skip friendly
		if uid in target_ids:
			continue  # Skip declared targets
		var u_status = u.get("status", 0)
		if u_status == GameStateData.UnitStatus.UNDEPLOYED or u_status == GameStateData.UnitStatus.IN_RESERVES:
			continue
		for m in u.get("models", []):
			if not m.get("alive", true):
				continue
			var mp = _get_model_position(m)
			if mp == Vector2.INF:
				continue
			var br = _model_bounding_radius_px(m.get("base_mm", 32), m.get("base_type", "circular"), m.get("base_dimensions", {}))
			non_target_enemies.append({"position": mp, "base_radius_px": br})

	# Get deployed models for collision checking (excluding this unit)
	var deployed_models = _get_deployed_models_excluding_unit(snapshot, unit_id)

	# Get target model info for engagement range checking
	var target_model_info = []  # Array of {position, base_radius_px} for all target models
	for target_id in target_ids:
		var target_unit = snapshot.get("units", {}).get(target_id, {})
		for tm in target_unit.get("models", []):
			if not tm.get("alive", true):
				continue
			var tp = _get_model_position(tm)
			if tp == Vector2.INF:
				continue
			var br = _model_bounding_radius_px(tm.get("base_mm", 32), tm.get("base_type", "circular"), tm.get("base_dimensions", {}))
			target_model_info.append({"position": tp, "base_radius_px": br, "target_id": target_id})

	var move_budget_px = rolled_distance * PIXELS_PER_INCH
	var first_model = alive_models[0]
	var base_mm = first_model.get("base_mm", 32)
	var base_type = first_model.get("base_type", "circular")
	var base_dimensions = first_model.get("base_dimensions", {})
	var my_base_radius_px = _model_bounding_radius_px(base_mm, base_type, base_dimensions)

	# --- Compute destinations for each model ---
	# Strategy: move each model toward the primary target, stopping at engagement range
	# The lead model should get into base-to-base or just within engagement range
	# Remaining models maintain coherency and follow

	var per_model_paths = {}
	var placed_positions = []  # Track placed positions for intra-unit overlap avoidance

	# Sort models by distance to primary target (closest first)
	var model_distances = []
	for model in alive_models:
		var mid = model.get("id", "")
		var mpos = _get_model_position(model)
		var dist = mpos.distance_to(primary_target_pos)
		model_distances.append({"model": model, "id": mid, "pos": mpos, "dist": dist})
	model_distances.sort_custom(func(a, b): return a.dist < b.dist)

	var engagement_range_px = ENGAGEMENT_RANGE_PX  # 1" = 40px
	var any_model_in_er = {}  # target_id -> bool (track if we've gotten a model in ER per target)
	for tid in target_ids:
		any_model_in_er[tid] = false

	for md in model_distances:
		var model = md.model
		var mid = md.id
		var start_pos = md.pos
		var start_dist_to_target = md.dist

		# Direction toward primary target
		var direction = (primary_target_pos - start_pos).normalized()
		if direction == Vector2.ZERO:
			direction = Vector2.RIGHT

		# Calculate ideal destination: close to target within engagement range
		# Edge-to-edge engagement range: center distance = ER + my_radius + target_radius
		var closest_target_model = _find_closest_target_model_info(start_pos, target_model_info)
		var target_base_radius = closest_target_model.base_radius_px if not closest_target_model.is_empty() else 20.0
		var ideal_center_dist = engagement_range_px + my_base_radius_px + target_base_radius - 2.0  # Slight buffer inside ER
		var target_for_model = closest_target_model.position if not closest_target_model.is_empty() else primary_target_pos

		var dir_to_target = (target_for_model - start_pos).normalized()
		if dir_to_target == Vector2.ZERO:
			dir_to_target = Vector2.RIGHT

		var target_center_dist = start_pos.distance_to(target_for_model)
		var desired_move_dist = target_center_dist - ideal_center_dist
		# Clamp to move budget
		var actual_move_dist = clamp(desired_move_dist, 0.0, move_budget_px)

		var candidate_pos = start_pos + dir_to_target * actual_move_dist

		# Clamp to board bounds
		candidate_pos.x = clamp(candidate_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		candidate_pos.y = clamp(candidate_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

		# Check constraints and adjust
		candidate_pos = _adjust_charge_position(
			candidate_pos, start_pos, move_budget_px, my_base_radius_px,
			target_model_info, non_target_enemies, deployed_models,
			placed_positions, base_mm, base_type, base_dimensions
		)

		# Verify the model ends closer to at least one target than it started
		var ends_closer = false
		for tp_info in target_model_info:
			var original_dist = start_pos.distance_to(tp_info.position)
			var new_dist = candidate_pos.distance_to(tp_info.position)
			if new_dist < original_dist:
				ends_closer = true
				break

		if not ends_closer and start_pos.distance_to(candidate_pos) > 1.0:
			# Fallback: don't move this model (stay in place is valid if it was already close)
			candidate_pos = start_pos

		# Track which targets have a model in engagement range
		for tp_info in target_model_info:
			var edge_dist_px = candidate_pos.distance_to(tp_info.position) - my_base_radius_px - tp_info.base_radius_px
			if edge_dist_px <= engagement_range_px:
				any_model_in_er[tp_info.target_id] = true

		# Record the path (start -> end)
		per_model_paths[mid] = [
			[start_pos.x, start_pos.y],
			[candidate_pos.x, candidate_pos.y]
		]

		placed_positions.append({
			"position": candidate_pos,
			"base_mm": base_mm,
			"base_type": base_type,
			"base_dimensions": base_dimensions
		})

	# Verify we achieved engagement range with all targets
	var all_targets_reached = true
	for tid in target_ids:
		if not any_model_in_er.get(tid, false):
			all_targets_reached = false
			print("AIDecisionMaker: Charge move for %s failed to reach target %s engagement range" % [unit_name, tid])
			break

	if not all_targets_reached:
		# Cannot construct a valid charge move — this shouldn't happen if the roll was sufficient
		# but may occur due to geometry constraints. The phase will handle the failure.
		print("AIDecisionMaker: Submitting charge move anyway — phase will validate and handle failure")

	var target_names = []
	for tid in target_ids:
		var t = snapshot.get("units", {}).get(tid, {})
		target_names.append(t.get("meta", {}).get("name", tid))

	return {
		"type": "APPLY_CHARGE_MOVE",
		"actor_unit_id": unit_id,
		"payload": {
			"per_model_paths": per_model_paths,
			"per_model_rotations": {},
		},
		"_ai_description": "%s charges into %s (rolled %d\")" % [unit_name, ", ".join(target_names), rolled_distance]
	}

static func _find_closest_target_model_info(pos: Vector2, target_model_info: Array) -> Dictionary:
	"""Find the closest target model info dict to a given position."""
	var closest = {}
	var closest_dist = INF
	for info in target_model_info:
		var d = pos.distance_to(info.position)
		if d < closest_dist:
			closest_dist = d
			closest = info
	return closest

static func _adjust_charge_position(
	candidate: Vector2, start_pos: Vector2, move_budget_px: float,
	my_base_radius_px: float, target_model_info: Array,
	non_target_enemies: Array, deployed_models: Array,
	placed_positions: Array, base_mm: int, base_type: String,
	base_dimensions: Dictionary
) -> Vector2:
	"""Adjust a candidate charge position to satisfy constraints:
	- Must not exceed move budget from start
	- Must not overlap with deployed models or already-placed models
	- Must not end in engagement range of non-target enemies
	Returns the adjusted position."""

	var pos = candidate

	# 1. Ensure within move budget
	var move_dist = start_pos.distance_to(pos)
	if move_dist > move_budget_px:
		var dir = (pos - start_pos).normalized()
		pos = start_pos + dir * move_budget_px

	# 2. Check for non-target enemy engagement range violation
	var er_px = ENGAGEMENT_RANGE_PX
	for nte in non_target_enemies:
		var edge_dist = pos.distance_to(nte.position) - my_base_radius_px - nte.base_radius_px
		if edge_dist <= er_px:
			# Push away from non-target enemy
			var push_dir = (pos - nte.position).normalized()
			if push_dir == Vector2.ZERO:
				push_dir = Vector2.RIGHT
			var needed_dist = my_base_radius_px + nte.base_radius_px + er_px + 5.0  # 5px safety margin
			pos = nte.position + push_dir * needed_dist

			# Re-check move budget after push
			move_dist = start_pos.distance_to(pos)
			if move_dist > move_budget_px:
				var dir = (pos - start_pos).normalized()
				pos = start_pos + dir * move_budget_px

	# 3. Check for overlap with deployed models
	var all_obstacles = deployed_models + placed_positions
	if _position_collides_with_deployed(pos, base_mm, all_obstacles, 4.0, base_type, base_dimensions):
		# Spiral search for nearest free position
		var step = my_base_radius_px * 2.0 + 8.0
		for ring in range(1, 6):
			var ring_radius = step * ring * 0.5
			var points_in_ring = maxi(8, ring * 6)
			for p_idx in range(points_in_ring):
				var angle = (2.0 * PI * p_idx) / points_in_ring
				var test_pos = Vector2(
					pos.x + cos(angle) * ring_radius,
					pos.y + sin(angle) * ring_radius
				)
				# Check move budget
				if start_pos.distance_to(test_pos) > move_budget_px:
					continue
				# Check board bounds
				test_pos.x = clamp(test_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
				test_pos.y = clamp(test_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
				# Check no collision
				if not _position_collides_with_deployed(test_pos, base_mm, all_obstacles, 4.0, base_type, base_dimensions):
					# Check no non-target ER violation
					var nte_ok = true
					for nte in non_target_enemies:
						var edge_dist = test_pos.distance_to(nte.position) - my_base_radius_px - nte.base_radius_px
						if edge_dist <= er_px:
							nte_ok = false
							break
					if nte_ok:
						return test_pos

	return pos

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
		# First pile in — compute movements toward nearest enemy (up to 3")
		if action_types.has("PILE_IN"):
			var a = action_types["PILE_IN"][0]
			var uid = a.get("unit_id", "")
			return _compute_pile_in_action(snapshot, uid, player)

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
		return _compute_consolidate_action(snapshot, uid, player)

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
		weapon_id = _generate_weapon_id(melee_weapon.get("name", "Close combat weapon"), melee_weapon.get("type", "Melee"))

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
# PILE-IN MOVEMENT COMPUTATION
# =============================================================================

static func _compute_pile_in_action(snapshot: Dictionary, unit_id: String, player: int) -> Dictionary:
	"""Compute pile-in movements for a unit. Each model moves up to 3" toward the
	closest enemy model (edge-to-edge). Models already in base contact stay put.
	Returns a PILE_IN action dict with the movements dictionary."""
	var unit = snapshot.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {
			"type": "PILE_IN",
			"unit_id": unit_id,
			"actor_unit_id": unit_id,
			"movements": {},
			"_ai_description": "Pile in (unit not found)"
		}

	var unit_name = unit.get("meta", {}).get("name", unit_id)
	var movements = _compute_pile_in_movements(snapshot, unit_id, unit, player)

	var description = ""
	if movements.is_empty():
		description = "%s pile in (all models holding position)" % unit_name
	else:
		description = "%s piles in toward enemy (%d models moved)" % [unit_name, movements.size()]

	print("AIDecisionMaker: %s" % description)

	return {
		"type": "PILE_IN",
		"unit_id": unit_id,
		"actor_unit_id": unit_id,
		"movements": movements,
		"_ai_description": description
	}

static func _compute_pile_in_movements(snapshot: Dictionary, unit_id: String, unit: Dictionary, player: int) -> Dictionary:
	"""Compute per-model pile-in destinations. Returns {model_id_string: Vector2} for models
	that should move. Models that stay put are omitted.

	Pile-in rules (10th edition):
	- Each model may move up to 3"
	- Each model must end closer to the closest enemy model than it started
	- Models already in base-to-base contact with an enemy cannot move
	- After pile-in, unit must still be in engagement range of at least one enemy
	- Unit coherency must be maintained
	- If a model CAN reach base-to-base contact within 3", it SHOULD"""

	var movements = {}
	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return movements

	var unit_owner = int(unit.get("owner", player))

	# Gather all enemy model info for distance calculations
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var has_fly = "FLY" in unit_keywords
	var enemy_models_info = []  # Array of {position: Vector2, base_radius_px: float, base_mm: int}
	for other_unit_id in snapshot.get("units", {}):
		var other_unit = snapshot.units[other_unit_id]
		if int(other_unit.get("owner", 0)) == unit_owner:
			continue  # Skip friendly
		# Skip undeployed / in reserves
		var other_status = other_unit.get("status", 0)
		if other_status == GameStateData.UnitStatus.UNDEPLOYED or other_status == GameStateData.UnitStatus.IN_RESERVES:
			continue
		# Skip AIRCRAFT unless our unit has FLY (T4-4 rule)
		var other_keywords = other_unit.get("meta", {}).get("keywords", [])
		if "AIRCRAFT" in other_keywords and not has_fly:
			continue
		for em in other_unit.get("models", []):
			if not em.get("alive", true):
				continue
			var ep = _get_model_position(em)
			if ep == Vector2.INF:
				continue
			var ebr = _model_bounding_radius_px(em.get("base_mm", 32), em.get("base_type", "circular"), em.get("base_dimensions", {}))
			enemy_models_info.append({
				"position": ep,
				"base_radius_px": ebr,
				"base_mm": em.get("base_mm", 32),
			})

	if enemy_models_info.is_empty():
		print("AIDecisionMaker: Pile-in for %s — no enemy models found" % unit_id)
		return movements

	# Get deployed models for collision checking (excluding this unit)
	var deployed_models = _get_deployed_models_excluding_unit(snapshot, unit_id)

	var pile_in_range_px = 3.0 * PIXELS_PER_INCH  # 3" in pixels
	var base_contact_threshold_px = 0.25 * PIXELS_PER_INCH  # Match FightPhase tolerance (0.25")

	# Track placed positions to avoid intra-unit collisions
	var placed_positions = []

	# Sort models by distance to nearest enemy (furthest first so they trail behind)
	var model_entries = []
	for model in alive_models:
		var mid = model.get("id", "")
		var mpos = _get_model_position(model)
		if mpos == Vector2.INF:
			continue
		var mbr = _model_bounding_radius_px(model.get("base_mm", 32), model.get("base_type", "circular"), model.get("base_dimensions", {}))

		# Find closest enemy model (edge-to-edge)
		var closest_enemy_dist_px = INF
		var closest_enemy_pos = Vector2.INF
		var closest_enemy_radius = 0.0
		for ei in enemy_models_info:
			var edge_dist = mpos.distance_to(ei.position) - mbr - ei.base_radius_px
			if edge_dist < closest_enemy_dist_px:
				closest_enemy_dist_px = edge_dist
				closest_enemy_pos = ei.position
				closest_enemy_radius = ei.base_radius_px

		model_entries.append({
			"model": model,
			"id": mid,
			"pos": mpos,
			"base_radius_px": mbr,
			"closest_enemy_dist_px": closest_enemy_dist_px,
			"closest_enemy_pos": closest_enemy_pos,
			"closest_enemy_radius": closest_enemy_radius,
		})

	# Sort: models closest to enemies first (they get priority placement)
	model_entries.sort_custom(func(a, b): return a.closest_enemy_dist_px < b.closest_enemy_dist_px)

	for entry in model_entries:
		var mid = entry.id
		var start_pos = entry.pos
		var my_radius = entry.base_radius_px
		var closest_enemy_pos = entry.closest_enemy_pos
		var closest_enemy_radius = entry.closest_enemy_radius
		var closest_enemy_dist_px = entry.closest_enemy_dist_px
		var model = entry.model
		var base_mm = model.get("base_mm", 32)
		var base_type = model.get("base_type", "circular")
		var base_dimensions = model.get("base_dimensions", {})

		if closest_enemy_pos == Vector2.INF:
			# No enemy found for this model - skip
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		# Check if model is already in base contact with nearest enemy
		if closest_enemy_dist_px <= base_contact_threshold_px:
			# Model is in base contact — do not move (T4-5)
			print("AIDecisionMaker: Pile-in model %s already in base contact (dist=%.1fpx), holding" % [mid, closest_enemy_dist_px])
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		# Calculate direction toward closest enemy
		var direction = (closest_enemy_pos - start_pos).normalized()
		if direction == Vector2.ZERO:
			direction = Vector2.RIGHT

		# Calculate ideal destination: base-to-base contact with closest enemy
		# Center-to-center distance for base contact = my_radius + enemy_radius
		var b2b_center_dist = my_radius + closest_enemy_radius
		var current_center_dist = start_pos.distance_to(closest_enemy_pos)
		var desired_move_dist_px = current_center_dist - b2b_center_dist

		# Clamp to 3" pile-in limit
		var actual_move_dist_px = clampf(desired_move_dist_px, 0.0, pile_in_range_px)

		# If the model barely needs to move (sub-pixel), skip it
		if actual_move_dist_px < 1.0:
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		var candidate_pos = start_pos + direction * actual_move_dist_px

		# Clamp to board bounds
		candidate_pos.x = clampf(candidate_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		candidate_pos.y = clampf(candidate_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

		# Check collision with deployed models + already placed models from this unit
		var all_obstacles = deployed_models + placed_positions
		if _position_collides_with_deployed(candidate_pos, base_mm, all_obstacles, 2.0, base_type, base_dimensions):
			# Try to find a nearby collision-free position still closer to the enemy
			var found_alt = false
			var step = my_radius * 2.0 + 4.0
			for ring in range(1, 5):
				var ring_radius = step * ring * 0.4
				var points_in_ring = maxi(8, ring * 6)
				for p_idx in range(points_in_ring):
					var angle = (2.0 * PI * p_idx) / points_in_ring
					var test_pos = Vector2(
						candidate_pos.x + cos(angle) * ring_radius,
						candidate_pos.y + sin(angle) * ring_radius
					)
					# Check move budget
					if start_pos.distance_to(test_pos) > pile_in_range_px:
						continue
					# Must be closer to enemy than start
					if test_pos.distance_to(closest_enemy_pos) >= start_pos.distance_to(closest_enemy_pos):
						continue
					# Clamp to board
					test_pos.x = clampf(test_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
					test_pos.y = clampf(test_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
					# Check collision
					if not _position_collides_with_deployed(test_pos, base_mm, all_obstacles, 2.0, base_type, base_dimensions):
						candidate_pos = test_pos
						found_alt = true
						break
				if found_alt:
					break

			if not found_alt:
				# Cannot find collision-free position — hold position
				print("AIDecisionMaker: Pile-in model %s collision — holding position" % mid)
				placed_positions.append({
					"position": start_pos,
					"base_mm": base_mm,
					"base_type": base_type,
					"base_dimensions": base_dimensions,
				})
				continue

		# Verify the model ends closer to the closest enemy than it started
		var new_dist_to_enemy = candidate_pos.distance_to(closest_enemy_pos)
		var old_dist_to_enemy = start_pos.distance_to(closest_enemy_pos)
		if new_dist_to_enemy >= old_dist_to_enemy:
			# Movement doesn't bring us closer — skip (validation would reject)
			print("AIDecisionMaker: Pile-in model %s would not end closer to enemy, skipping" % mid)
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		# Record the movement
		# FightPhase expects model_id as string index into the models array
		# We need to find the index of this model in the unit's models array
		var model_index = _find_model_index_in_unit(unit, mid)
		if model_index == -1:
			print("AIDecisionMaker: Pile-in model %s index not found, skipping" % mid)
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		var move_inches = start_pos.distance_to(candidate_pos) / PIXELS_PER_INCH
		print("AIDecisionMaker: Pile-in model %s (idx %d) moves %.1f\" toward enemy" % [mid, model_index, move_inches])

		movements[str(model_index)] = candidate_pos
		placed_positions.append({
			"position": candidate_pos,
			"base_mm": base_mm,
			"base_type": base_type,
			"base_dimensions": base_dimensions,
		})

	return movements

static func _find_model_index_in_unit(unit: Dictionary, model_id: String) -> int:
	"""Find the index of a model in a unit's models array by its id field."""
	var models = unit.get("models", [])
	for i in range(models.size()):
		if models[i].get("id", "") == model_id:
			return i
	# Fallback: try matching as string index
	if model_id.is_valid_int():
		var idx = int(model_id)
		if idx >= 0 and idx < models.size():
			return idx
	return -1

# =============================================================================
# CONSOLIDATION MOVEMENT COMPUTATION
# =============================================================================

static func _compute_consolidate_action(snapshot: Dictionary, unit_id: String, player: int) -> Dictionary:
	"""Compute consolidation movements for a unit after fighting.
	Consolidation has two modes:
	- ENGAGEMENT: If any enemy is within 4" (3" move + 1" engagement range),
	  move each model up to 3" toward closest enemy (same rules as pile-in).
	- OBJECTIVE: If no enemy reachable, move each model up to 3" toward
	  the closest objective marker.
	Returns a CONSOLIDATE action dict with the movements dictionary."""
	var unit = snapshot.get("units", {}).get(unit_id, {})
	if unit.is_empty():
		return {
			"type": "CONSOLIDATE",
			"unit_id": unit_id,
			"movements": {},
			"_ai_description": "Consolidate (unit not found)"
		}

	var unit_name = unit.get("meta", {}).get("name", unit_id)

	# T4-4: Aircraft cannot Consolidate
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	if "AIRCRAFT" in unit_keywords:
		print("AIDecisionMaker: %s is AIRCRAFT — skipping consolidation" % unit_name)
		return {
			"type": "CONSOLIDATE",
			"unit_id": unit_id,
			"movements": {},
			"_ai_description": "%s skips consolidation (AIRCRAFT)" % unit_name
		}

	# Determine consolidation mode: engagement or objective
	var mode = _determine_ai_consolidate_mode(snapshot, unit, player)
	var movements = {}

	if mode == "ENGAGEMENT":
		# Reuse pile-in logic — consolidation in engagement mode follows the same
		# rules: each model moves up to 3" toward the closest enemy model
		movements = _compute_pile_in_movements(snapshot, unit_id, unit, player)
	elif mode == "OBJECTIVE":
		movements = _compute_consolidate_movements_objective(snapshot, unit_id, unit, player)

	var description = ""
	if movements.is_empty():
		description = "%s consolidates (all models holding position)" % unit_name
	else:
		var mode_label = "toward enemy" if mode == "ENGAGEMENT" else "toward objective"
		description = "%s consolidates %s (%d models moved)" % [unit_name, mode_label, movements.size()]

	print("AIDecisionMaker: %s" % description)

	return {
		"type": "CONSOLIDATE",
		"unit_id": unit_id,
		"movements": movements,
		"_ai_description": description
	}

static func _determine_ai_consolidate_mode(snapshot: Dictionary, unit: Dictionary, player: int) -> String:
	"""Determine whether the AI should consolidate toward enemies (ENGAGEMENT) or
	toward the nearest objective (OBJECTIVE).
	- ENGAGEMENT: at least one alive enemy model is within 4" (3" move + 1" ER)
	  of at least one alive friendly model in this unit.
	- OBJECTIVE: no enemy is reachable but an objective exists.
	- NONE: neither target is available."""
	var unit_owner = int(unit.get("owner", player))
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var has_fly = "FLY" in unit_keywords

	var engagement_check_range_px = 4.0 * PIXELS_PER_INCH  # 3" move + 1" ER

	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return "NONE"

	# Check if any enemy model is within 4" of any of our models (edge-to-edge)
	for model in alive_models:
		var mpos = _get_model_position(model)
		if mpos == Vector2.INF:
			continue
		var mbr = _model_bounding_radius_px(model.get("base_mm", 32), model.get("base_type", "circular"), model.get("base_dimensions", {}))

		for other_unit_id in snapshot.get("units", {}):
			var other_unit = snapshot.units[other_unit_id]
			if int(other_unit.get("owner", 0)) == unit_owner:
				continue  # Skip friendly
			var other_status = other_unit.get("status", 0)
			if other_status == GameStateData.UnitStatus.UNDEPLOYED or other_status == GameStateData.UnitStatus.IN_RESERVES:
				continue
			var other_keywords = other_unit.get("meta", {}).get("keywords", [])
			if "AIRCRAFT" in other_keywords and not has_fly:
				continue
			for em in other_unit.get("models", []):
				if not em.get("alive", true):
					continue
				var ep = _get_model_position(em)
				if ep == Vector2.INF:
					continue
				var ebr = _model_bounding_radius_px(em.get("base_mm", 32), em.get("base_type", "circular"), em.get("base_dimensions", {}))
				var edge_dist_px = mpos.distance_to(ep) - mbr - ebr
				if edge_dist_px <= engagement_check_range_px:
					return "ENGAGEMENT"

	# No enemy reachable — check for objectives
	var objectives = _get_objectives(snapshot)
	if not objectives.is_empty():
		return "OBJECTIVE"

	return "NONE"

static func _compute_consolidate_movements_objective(snapshot: Dictionary, unit_id: String, unit: Dictionary, player: int) -> Dictionary:
	"""Compute per-model consolidation destinations when moving toward the closest
	objective (fallback mode when no enemy is within engagement reach).
	Returns {model_id_string: Vector2} for models that should move."""
	var movements = {}
	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return movements

	var objectives = _get_objectives(snapshot)
	if objectives.is_empty():
		print("AIDecisionMaker: Consolidate (objective) for %s — no objectives found" % unit_id)
		return movements

	# Get deployed models for collision checking (excluding this unit)
	var deployed_models = _get_deployed_models_excluding_unit(snapshot, unit_id)

	var consolidate_range_px = 3.0 * PIXELS_PER_INCH  # 3" in pixels

	# Track placed positions to avoid intra-unit collisions
	var placed_positions = []

	# Find the closest objective to the unit centroid to use as a consistent target
	var centroid = _get_unit_centroid(unit)
	var target_obj_pos = _nearest_objective_pos(centroid, objectives)
	if target_obj_pos == Vector2.INF:
		return movements

	# Sort models by distance to target objective (furthest first — they benefit most from movement)
	var model_entries = []
	for model in alive_models:
		var mid = model.get("id", "")
		var mpos = _get_model_position(model)
		if mpos == Vector2.INF:
			continue
		var dist_to_obj = mpos.distance_to(target_obj_pos)
		model_entries.append({
			"model": model,
			"id": mid,
			"pos": mpos,
			"dist_to_obj": dist_to_obj,
		})

	# Sort: models closest to objective first (they get priority placement near objective)
	model_entries.sort_custom(func(a, b): return a.dist_to_obj < b.dist_to_obj)

	for entry in model_entries:
		var mid = entry.id
		var start_pos = entry.pos
		var model = entry.model
		var base_mm = model.get("base_mm", 32)
		var base_type = model.get("base_type", "circular")
		var base_dimensions = model.get("base_dimensions", {})
		var my_radius = _model_bounding_radius_px(base_mm, base_type, base_dimensions)

		# Calculate direction toward the target objective
		var direction = (target_obj_pos - start_pos).normalized()
		if direction == Vector2.ZERO:
			# Already exactly on the objective — hold position
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		# Calculate how far we want to move (up to 3", toward objective)
		var dist_to_target = start_pos.distance_to(target_obj_pos)
		var desired_move_px = minf(dist_to_target, consolidate_range_px)

		# If the model barely needs to move (sub-pixel), skip it
		if desired_move_px < 1.0:
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		var candidate_pos = start_pos + direction * desired_move_px

		# Clamp to board bounds
		candidate_pos.x = clampf(candidate_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		candidate_pos.y = clampf(candidate_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

		# Check collision with deployed models + already placed models from this unit
		var all_obstacles = deployed_models + placed_positions
		if _position_collides_with_deployed(candidate_pos, base_mm, all_obstacles, 2.0, base_type, base_dimensions):
			# Try to find a nearby collision-free position still closer to objective
			var found_alt = false
			var step = my_radius * 2.0 + 4.0
			for ring in range(1, 5):
				var ring_radius = step * ring * 0.4
				var points_in_ring = maxi(8, ring * 6)
				for p_idx in range(points_in_ring):
					var angle = (2.0 * PI * p_idx) / points_in_ring
					var test_pos = Vector2(
						candidate_pos.x + cos(angle) * ring_radius,
						candidate_pos.y + sin(angle) * ring_radius
					)
					# Check move budget
					if start_pos.distance_to(test_pos) > consolidate_range_px:
						continue
					# Must be closer to objective than start
					if test_pos.distance_to(target_obj_pos) >= start_pos.distance_to(target_obj_pos):
						continue
					# Clamp to board
					test_pos.x = clampf(test_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
					test_pos.y = clampf(test_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
					# Check collision
					if not _position_collides_with_deployed(test_pos, base_mm, all_obstacles, 2.0, base_type, base_dimensions):
						candidate_pos = test_pos
						found_alt = true
						break
				if found_alt:
					break

			if not found_alt:
				# Cannot find collision-free position — hold position
				print("AIDecisionMaker: Consolidate model %s collision — holding position" % mid)
				placed_positions.append({
					"position": start_pos,
					"base_mm": base_mm,
					"base_type": base_type,
					"base_dimensions": base_dimensions,
				})
				continue

		# Verify the model ends closer to the objective than it started
		var new_dist_to_obj = candidate_pos.distance_to(target_obj_pos)
		var old_dist_to_obj = start_pos.distance_to(target_obj_pos)
		if new_dist_to_obj >= old_dist_to_obj:
			# Movement doesn't bring us closer — skip
			print("AIDecisionMaker: Consolidate model %s would not end closer to objective, skipping" % mid)
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		# Record the movement
		var model_index = _find_model_index_in_unit(unit, mid)
		if model_index == -1:
			print("AIDecisionMaker: Consolidate model %s index not found, skipping" % mid)
			placed_positions.append({
				"position": start_pos,
				"base_mm": base_mm,
				"base_type": base_type,
				"base_dimensions": base_dimensions,
			})
			continue

		var move_inches = start_pos.distance_to(candidate_pos) / PIXELS_PER_INCH
		print("AIDecisionMaker: Consolidate model %s (idx %d) moves %.1f\" toward objective" % [mid, model_index, move_inches])

		movements[str(model_index)] = candidate_pos
		placed_positions.append({
			"position": candidate_pos,
			"base_mm": base_mm,
			"base_type": base_type,
			"base_dimensions": base_dimensions,
		})

	return movements

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

static func _generate_weapon_id(weapon_name: String, weapon_type: String = "") -> String:
	var weapon_id = weapon_name.to_lower()
	weapon_id = weapon_id.replace(" ", "_")
	weapon_id = weapon_id.replace("-", "_")
	weapon_id = weapon_id.replace("–", "_")
	weapon_id = weapon_id.replace("'", "")
	# Append weapon type suffix to prevent collisions between ranged/melee variants
	if weapon_type != "":
		weapon_id += "_" + weapon_type.to_lower()
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
