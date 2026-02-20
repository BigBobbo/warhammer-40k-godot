class_name AIDecisionMaker
extends RefCounted

# AIDecisionMaker - Pure decision logic for the AI player
# No scene tree access, no signals. Takes data in, returns action dictionaries out.
# All methods are static for use without instantiation.

# --- Constants ---
const AIAbilityAnalyzerData = preload("res://scripts/AIAbilityAnalyzer.gd")
const PIXELS_PER_INCH: float = 40.0
const ENGAGEMENT_RANGE_PX: float = 40.0  # 1 inch
const CHARGE_RANGE_PX: float = 480.0     # 12 inches
const COHERENCY_RANGE_PX: float = 80.0   # 2 inches
const BOARD_WIDTH_PX: float = 1760.0     # 44 inches
const BOARD_HEIGHT_PX: float = 2400.0    # 60 inches
const OBJECTIVE_RANGE_PX: float = 120.0  # 3 inches - objective control range in 10e
const OBJECTIVE_CONTROL_RANGE_PX: float = 151.5  # 3.79" (3" + 20mm marker radius) in pixels
const BASE_MARGIN_PX: float = 30.0       # Safety margin from board edges

# Late-bound reference to RulesEngine autoload (avoids compile-time dependency)
static func _rules_engine():
	var main = Engine.get_main_loop()
	if main is SceneTree and main.root:
		return main.root.get_node_or_null("RulesEngine")
	return null

# Focus fire plan cache — built once per shooting phase, consumed per-unit
# Stores {unit_id: [{weapon_id, target_unit_id}]} mapping
static var _focus_fire_plan: Dictionary = {}
static var _focus_fire_plan_built: bool = false

# Grenade stratagem evaluation — checked once per shooting phase
static var _grenade_evaluated: bool = false

# Focus fire tuning constants
const OVERKILL_TOLERANCE: float = 1.3  # Allow up to 30% overkill before redirecting
const KILL_BONUS_MULTIPLIER: float = 2.0  # Bonus multiplier for targets we can actually kill
const LOW_HEALTH_BONUS: float = 1.5  # Bonus for targets below half health

# Weapon-target efficiency matching constants
# Weapon role classification thresholds
const ANTI_TANK_STRENGTH_THRESHOLD: int = 7     # S7+ suggests anti-tank
const ANTI_TANK_AP_THRESHOLD: int = 2            # AP-2+ suggests anti-tank
const ANTI_TANK_DAMAGE_THRESHOLD: float = 3.0    # D3+ suggests anti-tank
const ANTI_INFANTRY_DAMAGE_THRESHOLD: float = 1.0 # D1 is anti-infantry
const ANTI_INFANTRY_STRENGTH_CAP: int = 5        # S5 or below is anti-infantry oriented

# Efficiency multipliers for weapon-target matching
const EFFICIENCY_PERFECT_MATCH: float = 1.4      # Anti-tank vs vehicle, anti-infantry vs horde
const EFFICIENCY_GOOD_MATCH: float = 1.15        # Decent but not ideal pairing
const EFFICIENCY_NEUTRAL: float = 1.0            # No bonus or penalty
const EFFICIENCY_POOR_MATCH: float = 0.6         # Anti-infantry vs vehicle, etc.
const EFFICIENCY_TERRIBLE_MATCH: float = 0.35    # Total waste (e.g. lascannon vs grots)

# Damage waste penalty: multi-damage on single-wound models
const DAMAGE_WASTE_PENALTY_HEAVY: float = 0.4    # D3+ weapon vs 1W models
const DAMAGE_WASTE_PENALTY_MODERATE: float = 0.7  # D2 weapon vs 1W models

# Anti-keyword special rule bonus
const ANTI_KEYWORD_BONUS: float = 1.5            # Weapon has anti-X matching target type

# Weapon keyword scoring constants (SHOOT-5)
# Critical hit probability on a d6 (unmodified 6)
const CRIT_PROBABILITY: float = 1.0 / 6.0
# Rapid Fire / Melta: probability of being within half range when we know target is in range.
# Conservative estimate — assume 50% chance we're at half range unless we can measure.
const HALF_RANGE_FALLBACK_PROB: float = 0.5

# Movement AI tuning weights
const WEIGHT_UNCONTROLLED_OBJ: float = 10.0
const WEIGHT_CONTESTED_OBJ: float = 8.0
const WEIGHT_ENEMY_WEAK_OBJ: float = 7.0
const WEIGHT_HOME_UNDEFENDED: float = 9.0
const WEIGHT_ENEMY_STRONG_OBJ: float = -5.0
const WEIGHT_ALREADY_HELD_OBJ: float = -8.0
const WEIGHT_SCORING_URGENCY: float = 3.0
const WEIGHT_OC_EFFICIENCY: float = 2.0

# Threat range awareness constants (AI-TACTIC-4, MOV-2)
# Charge threat = enemy M + 12" charge + 1" engagement range
# Shooting threat = max weapon range of the enemy unit
# Penalty weights for moving into threat zones
const THREAT_CHARGE_PENALTY: float = 3.0    # Penalty for moving into charge threat range
const THREAT_SHOOTING_PENALTY: float = 1.0  # Lighter penalty for moving into shooting range (often unavoidable)
const THREAT_FRAGILE_BONUS: float = 1.5     # Extra penalty multiplier for fragile/high-value units in danger
const THREAT_MELEE_UNIT_IGNORE: float = 0.3 # Melee-focused units care less about being in charge range
const THREAT_SAFE_MARGIN_INCHES: float = 2.0 # Extra buffer beyond raw threat range for safety

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

static func decide(phase: int, snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	print("AIDecisionMaker: Deciding for phase %d, player %d, %d available actions" % [phase, player, available_actions.size()])
	for a in available_actions:
		print("  Available: %s" % a.get("type", "?"))

	# Reset focus fire plan cache and grenade flag when not in shooting phase
	if phase != GameStateData.Phase.SHOOTING:
		if _focus_fire_plan_built:
			_focus_fire_plan_built = false
			_focus_fire_plan.clear()
		_grenade_evaluated = false

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
	# AI strategy: Move scout units toward the nearest uncontrolled objective,
	# maintaining >9" from all enemy models. If no valid move exists, skip.

	# Step 1: If CONFIRM_SCOUT_MOVE is available, confirm it
	# (safety fallback — normally AIPlayer handles confirm after staging)
	for action in available_actions:
		if action.get("type") == "CONFIRM_SCOUT_MOVE":
			var uid = action.get("unit_id", "")
			return {
				"type": "CONFIRM_SCOUT_MOVE",
				"unit_id": uid,
				"_ai_description": "Confirm Scout move for %s" % uid
			}

	# Step 2: Find a BEGIN_SCOUT_MOVE action and compute destinations
	for action in available_actions:
		if action.get("type") == "BEGIN_SCOUT_MOVE":
			var unit_id = action.get("unit_id", "")
			var unit = snapshot.get("units", {}).get(unit_id, {})
			if unit.is_empty():
				continue

			var unit_name = unit.get("meta", {}).get("name", unit_id)
			var scout_distance = _get_scout_distance_from_unit(unit)
			if scout_distance <= 0.0:
				scout_distance = 6.0  # Default scout distance

			# Find the best objective to move toward
			var objectives = _get_objectives(snapshot)
			var enemies = _get_enemy_units(snapshot, player)
			var friendly_units = _get_units_for_player(snapshot, player)
			var target_pos = _find_best_scout_objective(unit, objectives, enemies, friendly_units, player, snapshot)

			if target_pos == Vector2.INF:
				print("AIDecisionMaker: No valid scout objective found for %s, skipping" % unit_name)
				return {
					"type": "SKIP_SCOUT_MOVE",
					"unit_id": unit_id,
					"_ai_description": "Skip Scout move for %s (no reachable objective)" % unit_name
				}

			# Compute model destinations toward the target
			var model_destinations = _compute_scout_movement(
				unit, unit_id, target_pos, scout_distance, snapshot, enemies
			)

			if model_destinations.is_empty():
				print("AIDecisionMaker: Could not compute valid scout destinations for %s, skipping" % unit_name)
				return {
					"type": "SKIP_SCOUT_MOVE",
					"unit_id": unit_id,
					"_ai_description": "Skip Scout move for %s (no valid path)" % unit_name
				}

			var centroid = _get_unit_centroid(unit)
			var dist_to_obj = centroid.distance_to(target_pos) / PIXELS_PER_INCH if centroid != Vector2.INF else 0.0

			print("AIDecisionMaker: %s scouting toward objective (%.1f\" away, Scout %d\")" % [
				unit_name, dist_to_obj, int(scout_distance)])

			return {
				"type": "BEGIN_SCOUT_MOVE",
				"unit_id": unit_id,
				"_ai_scout_destinations": model_destinations,
				"_ai_description": "%s scouts toward nearest objective (%.1f\" away)" % [unit_name, dist_to_obj]
			}

	# Step 3: If only SKIP actions remain (no BEGIN), skip remaining units
	for action in available_actions:
		if action.get("type") == "SKIP_SCOUT_MOVE":
			var uid = action.get("unit_id", "")
			return {
				"type": "SKIP_SCOUT_MOVE",
				"unit_id": uid,
				"_ai_description": "Skip Scout move for %s" % uid
			}

	# Step 4: If all scouts handled, end phase
	for action in available_actions:
		if action.get("type") == "END_SCOUT_PHASE":
			return {"type": "END_SCOUT_PHASE", "_ai_description": "End Scout Phase"}

	return {}

# =============================================================================
# SCOUT PHASE HELPERS
# =============================================================================

static func _get_scout_distance_from_unit(unit: Dictionary) -> float:
	"""Extract scout move distance in inches from unit abilities."""
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		var aname = ""
		var avalue = 0
		if ability is String:
			aname = ability
		elif ability is Dictionary:
			aname = ability.get("name", "")
			avalue = ability.get("value", 0)
		if aname.to_lower().begins_with("scout"):
			if avalue > 0:
				return float(avalue)
			# Try to parse distance from name, e.g. "Scout 6\"" or "Scout 6"
			var regex = RegEx.new()
			regex.compile("(?i)scout\\s+(\\d+)")
			var result = regex.search(aname)
			if result:
				return float(result.get_string(1))
			return 6.0
	return 0.0

static func _find_best_scout_objective(
	unit: Dictionary, objectives: Array, enemies: Dictionary,
	friendly_units: Dictionary, player: int, snapshot: Dictionary
) -> Vector2:
	"""Find the best objective for a scout unit to move toward.
	Prioritizes: uncontrolled > contested > enemy-weak objectives, with distance as tiebreaker.
	Avoids objectives that are already well-held by friendlies."""
	var centroid = _get_unit_centroid(unit)
	if centroid == Vector2.INF or objectives.is_empty():
		return Vector2.INF

	var obj_data = snapshot.get("board", {}).get("objectives", [])

	var best_pos = Vector2.INF
	var best_score = -INF

	for i in range(objectives.size()):
		var obj_pos = objectives[i]

		# Classify the objective
		var friendly_oc = _get_oc_at_position(obj_pos, friendly_units, player, true)
		var enemy_oc = _get_oc_at_position(obj_pos, enemies, player, false)
		var dist = centroid.distance_to(obj_pos)
		var dist_inches = dist / PIXELS_PER_INCH

		# Determine zone
		var obj_zone = "no_mans_land"
		if i < obj_data.size():
			obj_zone = obj_data[i].get("zone", "no_mans_land")

		var is_home = (player == 1 and obj_zone == "player1") or (player == 2 and obj_zone == "player2")
		var is_enemy_home = (player == 1 and obj_zone == "player2") or (player == 2 and obj_zone == "player1")

		# Score this objective for scouting
		var score = 0.0

		# Uncontrolled objectives are highest priority for scouts
		if friendly_oc == 0 and enemy_oc == 0:
			score += 10.0
		# Objectives not yet secured by friendlies
		elif friendly_oc == 0 and enemy_oc > 0:
			score += 7.0  # Enemy holds it, scout can get there first
		elif friendly_oc > 0 and friendly_oc <= enemy_oc:
			score += 5.0  # Contested, reinforce
		elif friendly_oc > enemy_oc and friendly_oc > 0:
			score -= 5.0  # Already held, lower priority

		# Prefer no-man's-land objectives (center of the board)
		if obj_zone == "no_mans_land":
			score += 3.0
		# Home objectives are less valuable to scout toward (already nearby)
		if is_home:
			score -= 4.0
		# Don't rush enemy home objectives with scouts
		if is_enemy_home:
			score -= 2.0

		# Closer objectives score better (within scout range is ideal)
		score -= dist_inches * 0.3

		if score > best_score:
			best_score = score
			best_pos = obj_pos

	return best_pos

static func _compute_scout_movement(
	unit: Dictionary, unit_id: String, target_pos: Vector2,
	scout_distance_inches: float, snapshot: Dictionary, enemies: Dictionary
) -> Dictionary:
	"""Compute model destinations for a scout move toward target_pos.
	Respects: scout distance limit, >9\" from all enemy models, board bounds, model overlap."""
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
	var move_px = scout_distance_inches * PIXELS_PER_INCH
	var dist_to_target = centroid.distance_to(target_pos)
	var actual_move_px = min(move_px, dist_to_target)
	var move_vector = direction * actual_move_px

	# Get deployed models for overlap checking
	var deployed_models = _get_deployed_models_excluding_unit(snapshot, unit_id)
	var first_model = alive_models[0] if alive_models.size() > 0 else {}
	var base_mm = first_model.get("base_mm", 32)
	var base_type = first_model.get("base_type", "circular")
	var base_dimensions = first_model.get("base_dimensions", {})

	# Build original positions map
	var original_positions = {}
	for model in alive_models:
		var mid = model.get("id", "")
		if mid != "":
			original_positions[mid] = _get_model_position(model)

	# Try the full move first, then progressively shorter moves
	var fractions_to_try = [1.0, 0.75, 0.5, 0.25]
	for fraction in fractions_to_try:
		var try_vector = move_vector * fraction
		var destinations = _try_scout_move_with_checks(
			alive_models, try_vector, enemies, unit, deployed_models,
			base_mm, base_type, base_dimensions, original_positions, move_px
		)
		if not destinations.is_empty():
			if fraction < 1.0:
				print("AIDecisionMaker: Scout using %.0f%% move to satisfy constraints" % (fraction * 100))
			return destinations

	# All fractions failed
	return {}

static func _try_scout_move_with_checks(
	alive_models: Array, move_vector: Vector2, enemies: Dictionary,
	unit: Dictionary, deployed_models: Array, base_mm: int,
	base_type: String, base_dimensions: Dictionary,
	original_positions: Dictionary = {}, move_cap_px: float = 0.0
) -> Dictionary:
	"""Try moving all models by move_vector, checking the >9\" enemy distance rule
	and model overlap. Returns model_id -> [x, y] destinations, or empty dict if invalid."""
	const SCOUT_ENEMY_DIST_INCHES: float = 9.0
	var destinations = {}
	var placed_models: Array = []

	var own_models = unit.get("models", [])
	var own_base_mm = own_models[0].get("base_mm", 32) if own_models.size() > 0 else 32
	var own_radius_inches = (own_base_mm / 2.0) / 25.4

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

		# Check movement distance does not exceed scout distance
		if move_cap_px > 0.0:
			var orig_pos = original_positions.get(model_id, model_pos)
			if orig_pos.distance_to(dest) > move_cap_px + 1.0:  # Small tolerance
				return {}

		# Check >9" from all enemy models (edge-to-edge)
		if _is_position_too_close_to_enemies_scout(dest, enemies, own_radius_inches, SCOUT_ENEMY_DIST_INCHES):
			return {}

		# Check overlap with deployed models and already-placed models
		var all_obstacles = deployed_models + placed_models
		if _position_collides_with_deployed(dest, base_mm, all_obstacles, 4.0, base_type, base_dimensions):
			# Try small perpendicular offsets to avoid the collision
			var orig_pos = original_positions.get(model_id, model_pos)
			var resolved_dest = _resolve_scout_collision(
				dest, move_vector, base_mm, base_type, base_dimensions,
				all_obstacles, enemies, own_radius_inches, SCOUT_ENEMY_DIST_INCHES,
				orig_pos, move_cap_px
			)
			if resolved_dest == Vector2.INF:
				return {}
			dest = resolved_dest

		destinations[model_id] = [dest.x, dest.y]
		placed_models.append({
			"position": dest,
			"base_mm": base_mm,
			"base_type": base_type,
			"base_dimensions": base_dimensions
		})

	return destinations

static func _is_position_too_close_to_enemies_scout(
	pos: Vector2, enemies: Dictionary,
	own_radius_inches: float, min_distance_inches: float
) -> bool:
	"""Check if a position is within min_distance_inches (edge-to-edge) of any enemy model.
	Used for scout moves where the minimum distance is 9\"."""
	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		for model in enemy.get("models", []):
			if not model.get("alive", true):
				continue
			var enemy_pos = _get_model_position(model)
			if enemy_pos == Vector2.INF:
				continue
			var enemy_base_mm = model.get("base_mm", 32)
			var enemy_radius_inches = (enemy_base_mm / 2.0) / 25.4
			var dist_px = pos.distance_to(enemy_pos)
			var dist_inches = dist_px / PIXELS_PER_INCH
			var edge_dist = dist_inches - own_radius_inches - enemy_radius_inches
			if edge_dist < min_distance_inches:
				return true
	return false

static func _resolve_scout_collision(
	dest: Vector2, move_vector: Vector2, base_mm: int,
	base_type: String, base_dimensions: Dictionary,
	obstacles: Array, enemies: Dictionary,
	own_radius_inches: float, min_enemy_dist_inches: float,
	original_pos: Vector2 = Vector2.INF, move_cap_px: float = 0.0
) -> Vector2:
	"""Try perpendicular offsets to avoid collision while satisfying scout >9\" rule."""
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

		# Check movement cap
		if original_pos != Vector2.INF and move_cap_px > 0.0:
			if original_pos.distance_to(candidate) > move_cap_px + 1.0:
				continue

		# Check model overlap
		if _position_collides_with_deployed(candidate, base_mm, obstacles, 4.0, base_type, base_dimensions):
			continue

		# Check >9" from enemies
		if _is_position_too_close_to_enemies_scout(candidate, enemies, own_radius_inches, min_enemy_dist_inches):
			continue

		return candidate

	return Vector2.INF

# =============================================================================
# COMMAND PHASE
# =============================================================================

static func _decide_command(snapshot: Dictionary, available_actions: Array, player: int) -> Dictionary:
	# Handle pending Command Re-roll decisions first
	# Note: The AIPlayer signal handler (_on_command_reroll_opportunity) handles this
	# with full roll context. This is a fallback in case available_actions still shows
	# the reroll options (e.g., if the signal handler hasn't fired yet).
	for action in available_actions:
		if action.get("type") == "USE_COMMAND_REROLL" or action.get("type") == "DECLINE_COMMAND_REROLL":
			# Fallback: decline the reroll (signal handler with context should have acted)
			var uid = action.get("actor_unit_id", action.get("unit_id", ""))
			return {
				"type": "DECLINE_COMMAND_REROLL",
				"actor_unit_id": uid,
				"_ai_description": "Decline Command Re-roll (command phase fallback)"
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

	# Step 0: Handle pending Command Re-roll decisions first (advance rolls)
	# The AIPlayer signal handler handles this with full context. This is a fallback.
	if action_types.has("USE_COMMAND_REROLL") or action_types.has("DECLINE_COMMAND_REROLL"):
		var uid = ""
		if action_types.has("USE_COMMAND_REROLL"):
			uid = action_types["USE_COMMAND_REROLL"][0].get("actor_unit_id", "")
		elif action_types.has("DECLINE_COMMAND_REROLL"):
			uid = action_types["DECLINE_COMMAND_REROLL"][0].get("actor_unit_id", "")
		return {
			"type": "DECLINE_COMMAND_REROLL",
			"actor_unit_id": uid,
			"_ai_description": "Decline Command Re-roll (movement phase fallback)"
		}

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
	# THREAT DATA: Calculate enemy threat zones once for all units (AI-TACTIC-4)
	# =========================================================================
	var threat_data = _calculate_enemy_threat_data(enemies)
	if not threat_data.is_empty():
		print("AIDecisionMaker: Calculated threat data for %d enemy units" % threat_data.size())
		for td in threat_data:
			print("  Enemy %s: charge_threat=%.1f\", shoot_threat=%.1f\", value=%.1f" % [
				td.unit_id, td.charge_threat_px / PIXELS_PER_INCH,
				td.shoot_threat_px / PIXELS_PER_INCH, td.unit_value])

	# =========================================================================
	# PHASE 1: GLOBAL OBJECTIVE EVALUATION
	# =========================================================================
	var obj_evaluations = _evaluate_all_objectives(snapshot, objectives, player, enemies, friendly_units, battle_round)

	# =========================================================================
	# PHASE 2: UNIT-TO-OBJECTIVE ASSIGNMENT (with threat awareness)
	# =========================================================================
	var assignments = _assign_units_to_objectives(
		snapshot, movable_units, obj_evaluations, objectives, enemies, friendly_units, player, battle_round, threat_data
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
				unit, unit_id, target_pos, advance_move, snapshot, enemies,
				0.0, threat_data, objectives
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

			# --- AI-TACTIC-4: Threat-aware hold check ---
			# Ranged units currently safe from charge threat should avoid moving
			# into charge range if the objective is far away and they have targets to shoot
			if not threat_data.is_empty() and "REMAIN_STATIONARY" in move_types:
				var has_ranged_for_threat = _unit_has_ranged_weapons(unit)
				var is_melee_unit = _unit_has_melee_weapons(unit) and not has_ranged_for_threat
				if has_ranged_for_threat and not is_melee_unit:
					var current_threat_eval = _evaluate_position_threat(centroid, threat_data, unit)
					# Estimate where we'd end up
					var move_dir = (target_pos - centroid).normalized() if centroid.distance_to(target_pos) > 1.0 else Vector2.ZERO
					var est_dest = centroid + move_dir * min(move_inches * PIXELS_PER_INCH, centroid.distance_to(target_pos))
					var dest_threat_eval = _evaluate_position_threat(est_dest, threat_data, unit)
					# If we're currently safe from charges but would move into charge range,
					# and we have shooting targets, consider staying put
					if current_threat_eval.charge_threat < 0.5 and dest_threat_eval.charge_threat >= 2.0:
						var max_wr = _get_max_weapon_range(unit)
						var has_shoot_targets = false
						for eid in enemies:
							var ec = _get_unit_centroid(enemies[eid])
							if ec != Vector2.INF and centroid.distance_to(ec) <= max_wr * PIXELS_PER_INCH:
								has_shoot_targets = true
								break
						if has_shoot_targets:
							print("AIDecisionMaker: %s avoiding charge danger — staying to shoot (charge threat would increase from %.1f to %.1f)" % [
								unit_name, current_threat_eval.charge_threat, dest_threat_eval.charge_threat])
							return {
								"type": "REMAIN_STATIONARY",
								"actor_unit_id": unit_id,
								"_ai_description": "%s holds position (avoiding charge threat, has shooting targets)" % unit_name
							}

			# --- MOV-1: Shooting range consideration ---
			# If the unit has ranged weapons and enemies in range, check if moving
			# would take it out of weapon range. Prefer holding for shooting if objective
			# is far away and we'd lose all targets.
			var has_ranged_weapons = _unit_has_ranged_weapons(unit)
			var max_weapon_range_inches = _get_max_weapon_range(unit) if has_ranged_weapons else 0.0
			if has_ranged_weapons and "REMAIN_STATIONARY" in move_types:
				if _should_hold_for_shooting(unit, centroid, target_pos, max_weapon_range_inches, enemies, move_inches, assignment):
					var enemies_in_range = _get_enemies_in_weapon_range(centroid, max_weapon_range_inches, enemies)
					return {
						"type": "REMAIN_STATIONARY",
						"actor_unit_id": unit_id,
						"_ai_description": "%s holds position for shooting (%d targets in %.0f\" range, obj %s too far)" % [
							unit_name, enemies_in_range.size(), max_weapon_range_inches, assigned_obj_id]
					}

			var model_destinations = _compute_movement_toward_target(
				unit, unit_id, target_pos, move_inches, snapshot, enemies,
				max_weapon_range_inches, threat_data, objectives
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
	player: int, battle_round: int, threat_data: Array = []
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

			# --- THREAT AWARENESS (AI-TACTIC-4, MOV-2) ---
			# Penalize assignments that route units into enemy threat zones
			if not threat_data.is_empty() and not already_on_obj:
				# Estimate where the unit would end up after moving toward this objective
				var move_direction = (obj_pos - centroid).normalized() if dist_px > 1.0 else Vector2.ZERO
				var move_px_cap = move_inches * PIXELS_PER_INCH
				var estimated_dest = centroid + move_direction * min(move_px_cap, dist_px)

				var dest_threat = _evaluate_position_threat(estimated_dest, threat_data, unit)
				var current_threat = _evaluate_position_threat(centroid, threat_data, unit)

				# Penalize moving INTO more danger than we're currently in
				var threat_increase = dest_threat.total_threat - current_threat.total_threat
				if threat_increase > 0.5:
					score -= threat_increase
					# Extra charge threat penalty: being chargeable is worse than being shot at
					if dest_threat.charge_threat > current_threat.charge_threat + 0.5:
						score -= (dest_threat.charge_threat - current_threat.charge_threat) * 0.5

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

	# --- Pre-check Fall Back and X abilities (AI-GAP-4) ---
	var all_units = snapshot.get("units", {})
	var fb_and_charge = AIAbilityAnalyzerData.can_fall_back_and_charge(unit_id, unit, all_units)
	var fb_and_shoot = AIAbilityAnalyzerData.can_fall_back_and_shoot(unit_id, unit, all_units)

	if on_objective:
		# Check if our OC at this objective would be reduced by falling back
		var friendly_oc_here = _get_oc_at_position(
			centroid, friendly_units, player, true
		)
		var enemy_oc_here = _get_oc_at_position(
			centroid, enemies, player, false
		)

		# If we're winning the OC war or tied, stay and hold
		# Exception: if the unit has Fall Back and Charge, falling back may be
		# tactically better (can charge back in, potentially killing the enemy)
		if friendly_oc_here >= enemy_oc_here and "REMAIN_STATIONARY" in move_types:
			if fb_and_charge:
				print("AIDecisionMaker: %s engaged on %s, winning OC (%d vs %d) but has Fall Back and Charge — may fall back to re-engage" % [unit_name, obj_id_held, friendly_oc_here, enemy_oc_here])
			else:
				print("AIDecisionMaker: %s engaged on %s but winning OC war (%d vs %d), holding" % [unit_name, obj_id_held, friendly_oc_here, enemy_oc_here])
				return {
					"type": "REMAIN_STATIONARY",
					"actor_unit_id": unit_id,
					"_ai_description": "%s holds %s while engaged (OC %d vs %d)" % [unit_name, obj_id_held, friendly_oc_here, enemy_oc_here]
				}

		# If we're losing OC but falling back would lose the objective entirely
		var oc_without_us = friendly_oc_here - unit_oc
		if oc_without_us <= 0 and "REMAIN_STATIONARY" in move_types:
			if fb_and_charge:
				# With Fall Back and Charge we can charge back onto the objective
				print("AIDecisionMaker: %s engaged on %s, only holder but has Fall Back and Charge — will fall back to re-engage" % [unit_name, obj_id_held])
			else:
				# We're the only one holding it — stay even if losing OC war
				print("AIDecisionMaker: %s engaged on %s, only holder (OC %d), staying" % [unit_name, obj_id_held, unit_oc])
				return {
					"type": "REMAIN_STATIONARY",
					"actor_unit_id": unit_id,
					"_ai_description": "%s stays on %s (only holder, OC: %d)" % [unit_name, obj_id_held, unit_oc]
				}

	# --- Ability-aware fall back decision (AI-GAP-4) ---
	var has_fb_ability = fb_and_charge or fb_and_shoot

	if has_fb_ability:
		var ability_text = []
		if fb_and_charge:
			ability_text.append("charge")
		if fb_and_shoot:
			ability_text.append("shoot")
		var ability_summary = " + ".join(ability_text)
		print("AIDecisionMaker: %s has Fall Back and %s — fall back is more attractive" % [unit_name, ability_summary])

	# Not on objective or better to fall back — fall back
	if "BEGIN_FALL_BACK" in move_types:
		var base_reason = "not on objective" if not on_objective else "losing OC war"

		# If the unit has Fall Back and X, enrich the reason
		var reason = base_reason
		if fb_and_charge:
			reason = "%s, can charge back (Fall Back and Charge)" % base_reason
		elif fb_and_shoot:
			reason = "%s, can still shoot (Fall Back and Shoot)" % base_reason

		# Compute fall-back destinations for all models (MOV-6)
		var fall_back_destinations = _compute_fall_back_destinations(
			unit, unit_id, snapshot, enemies, objectives, player
		)
		if not fall_back_destinations.is_empty():
			print("AIDecisionMaker: %s falling back with %d model destinations (%s)" % [unit_name, fall_back_destinations.size(), reason])
			return {
				"type": "BEGIN_FALL_BACK",
				"actor_unit_id": unit_id,
				"_ai_model_destinations": fall_back_destinations,
				"_ai_description": "%s falls back (%s)" % [unit_name, reason]
			}
		else:
			# Could not compute valid fall-back positions — remain stationary
			print("AIDecisionMaker: %s cannot find valid fall-back positions, remaining stationary" % unit_name)
			if "REMAIN_STATIONARY" in move_types:
				return {
					"type": "REMAIN_STATIONARY",
					"actor_unit_id": unit_id,
					"_ai_description": "%s remains stationary (no valid fall-back path)" % unit_name
				}

	if "REMAIN_STATIONARY" in move_types:
		return {
			"type": "REMAIN_STATIONARY",
			"actor_unit_id": unit_id,
			"_ai_description": "%s remains stationary (engaged, no fall back option)" % unit_name
		}

	return {}

# =============================================================================
# FALL-BACK MODEL POSITIONING (MOV-6)
# =============================================================================

static func _compute_fall_back_destinations(
	unit: Dictionary, unit_id: String, snapshot: Dictionary,
	enemies: Dictionary, objectives: Array, player: int
) -> Dictionary:
	"""Compute valid fall-back destinations for all models in an engaged unit.
	Each model must end:
	  1. Outside engagement range of ALL enemy models
	  2. Within its movement cap (M inches)
	  3. Not overlapping other models (friendly or enemy)
	  4. Within board bounds
	The AI picks a retreat direction: toward the nearest friendly objective or,
	failing that, directly away from the centroid of engaging enemies."""

	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return {}

	var move_inches = float(unit.get("meta", {}).get("stats", {}).get("move", 6))
	var move_px = move_inches * PIXELS_PER_INCH
	var centroid = _get_unit_centroid(unit)
	if centroid == Vector2.INF:
		return {}

	# Identify engaging enemy models and their centroid
	var engaging_enemy_centroid = _get_engaging_enemy_centroid(unit, unit_id, enemies)

	# Pick a retreat target: nearest uncontested friendly objective, or away from enemies
	var retreat_target = _pick_fall_back_target(centroid, engaging_enemy_centroid, objectives, enemies, player, snapshot)

	# Calculate retreat direction
	var retreat_direction: Vector2
	if retreat_target != Vector2.INF:
		retreat_direction = (retreat_target - centroid).normalized()
	else:
		# Fall back directly away from enemies
		if engaging_enemy_centroid != Vector2.INF:
			retreat_direction = (centroid - engaging_enemy_centroid).normalized()
		else:
			# Fallback: move toward own deployment zone (toward board edge)
			retreat_direction = Vector2(0, -1) if player == 1 else Vector2(0, 1)

	# Safety: if retreat direction is zero (target at our position), fall back
	# to moving directly away from enemies
	if retreat_direction.length_squared() < 0.01:
		if engaging_enemy_centroid != Vector2.INF:
			retreat_direction = (centroid - engaging_enemy_centroid).normalized()
		else:
			retreat_direction = Vector2(0, -1) if player == 1 else Vector2(0, 1)
		print("AIDecisionMaker: Retreat target at unit position, using away-from-enemy direction (%.2f, %.2f)" % [retreat_direction.x, retreat_direction.y])

	# Get deployed model positions for collision checking (excluding this unit)
	var deployed_models = _get_deployed_models_excluding_unit(snapshot, unit_id)
	var first_model = alive_models[0] if alive_models.size() > 0 else {}
	var base_mm = first_model.get("base_mm", 32)
	var base_type = first_model.get("base_type", "circular")
	var base_dimensions = first_model.get("base_dimensions", {})

	# Build original positions map
	var original_positions = {}
	for model in alive_models:
		var mid = model.get("id", "")
		if mid != "":
			original_positions[mid] = _get_model_position(model)

	# Get terrain features for blocking checks
	var terrain_features = snapshot.get("board", {}).get("terrain_features", [])
	var unit_keywords = unit.get("meta", {}).get("keywords", [])

	# Try the primary retreat direction first, then try alternate angles
	var directions_to_try = _build_fall_back_directions(retreat_direction)

	for direction in directions_to_try:
		# Try full move, then progressively shorter
		var fractions = [1.0, 0.75, 0.5, 0.25]
		for fraction in fractions:
			var move_vector = direction * move_px * fraction
			var destinations = _try_fall_back_positions(
				alive_models, move_vector, enemies, unit,
				deployed_models, base_mm, base_type, base_dimensions,
				original_positions, move_px, terrain_features, unit_keywords
			)
			if not destinations.is_empty():
				if fraction < 1.0:
					print("AIDecisionMaker: Fall-back using %.0f%% move in direction (%.1f, %.1f)" % [fraction * 100, direction.x, direction.y])
				return destinations

	# All directions failed
	print("AIDecisionMaker: Could not find valid fall-back destinations for %s" % unit_id)
	return {}

static func _get_engaging_enemy_centroid(unit: Dictionary, unit_id: String, enemies: Dictionary) -> Vector2:
	"""Find the centroid of all enemy models currently within engagement range of this unit."""
	var engaging_positions = []
	var alive_models = _get_alive_models_with_positions(unit)
	var own_models_data = unit.get("models", [])
	var own_base_mm = own_models_data[0].get("base_mm", 32) if own_models_data.size() > 0 else 32
	var own_radius_px = (own_base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)

	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		for enemy_model in enemy.get("models", []):
			if not enemy_model.get("alive", true):
				continue
			var enemy_pos = _get_model_position(enemy_model)
			if enemy_pos == Vector2.INF:
				continue
			var enemy_base_mm = enemy_model.get("base_mm", 32)
			var enemy_radius_px = (enemy_base_mm / 2.0) * (PIXELS_PER_INCH / 25.4)
			var er_threshold = own_radius_px + enemy_radius_px + ENGAGEMENT_RANGE_PX

			# Check if this enemy model is within ER of any of our models
			for own_model in alive_models:
				var own_pos = _get_model_position(own_model)
				if own_pos == Vector2.INF:
					continue
				if own_pos.distance_to(enemy_pos) < er_threshold:
					engaging_positions.append(enemy_pos)
					break  # Only count this enemy model once

	if engaging_positions.is_empty():
		return Vector2.INF

	var sum_val = Vector2.ZERO
	for pos in engaging_positions:
		sum_val += pos
	return sum_val / engaging_positions.size()

static func _pick_fall_back_target(
	centroid: Vector2, enemy_centroid: Vector2,
	objectives: Array, enemies: Dictionary, player: int,
	snapshot: Dictionary
) -> Vector2:
	"""Pick the best retreat target for a falling-back unit.
	Priority: nearest friendly-controlled or uncontrolled objective that is
	away from the engaging enemy. If none found, returns Vector2.INF (caller
	will default to moving directly away from enemies)."""
	var friendly_units = _get_units_for_player(snapshot, player)
	var best_target = Vector2.INF
	var best_score = -INF

	# Compute "away from enemy" direction for directional scoring
	var away_from_enemy = Vector2.ZERO
	if enemy_centroid != Vector2.INF:
		away_from_enemy = (centroid - enemy_centroid).normalized()

	for obj_pos in objectives:
		# Skip objectives at or very near our current position — can't retreat
		# TO where we already are (would produce a zero retreat direction)
		var dist_to_obj = centroid.distance_to(obj_pos)
		if dist_to_obj < ENGAGEMENT_RANGE_PX:
			continue

		# Skip objectives that are closer to the engaging enemy than to us
		if enemy_centroid != Vector2.INF:
			var enemy_dist_to_obj = enemy_centroid.distance_to(obj_pos)
			var our_dist_to_obj = dist_to_obj
			# Only consider objectives that are roughly "behind" us relative to the enemy
			if enemy_dist_to_obj < our_dist_to_obj * 0.7:
				continue

		# Prefer closer objectives
		var score = -dist_to_obj

		# Directional bonus: strongly prefer objectives in the "away from enemy" direction
		if away_from_enemy != Vector2.ZERO and dist_to_obj > 0.01:
			var dir_to_obj = (obj_pos - centroid).normalized()
			var alignment = away_from_enemy.dot(dir_to_obj)  # -1 to +1
			# Bonus of up to +300 for objectives directly away from enemy
			# Penalty of up to -300 for objectives directly toward the enemy
			score += alignment * 300.0

		# Prefer objectives we already control
		var friendly_oc = _get_oc_at_position(obj_pos, friendly_units, player, true)
		var enemy_oc = _get_oc_at_position(obj_pos, enemies, player, false)
		if friendly_oc > enemy_oc:
			score += 200.0  # Strongly prefer friendly-controlled objectives
		elif friendly_oc == 0 and enemy_oc == 0:
			score += 100.0  # Uncontrolled objectives are next best

		if score > best_score:
			best_score = score
			best_target = obj_pos

	return best_target

static func _build_fall_back_directions(primary_direction: Vector2) -> Array:
	"""Build an array of retreat directions to try, starting with the primary
	and branching out to alternates at +/-30, +/-60, +/-90, +/-120, +/-150, and 180 degrees."""
	var directions = [primary_direction]
	var angles = [
		deg_to_rad(30), deg_to_rad(-30),
		deg_to_rad(60), deg_to_rad(-60),
		deg_to_rad(90), deg_to_rad(-90),
		deg_to_rad(120), deg_to_rad(-120),
		deg_to_rad(150), deg_to_rad(-150),
		deg_to_rad(180)
	]
	for angle in angles:
		directions.append(primary_direction.rotated(angle))
	return directions

static func _try_fall_back_positions(
	alive_models: Array, move_vector: Vector2, enemies: Dictionary,
	unit: Dictionary, deployed_models: Array, base_mm: int,
	base_type: String, base_dimensions: Dictionary,
	original_positions: Dictionary, move_cap_px: float,
	terrain_features: Array, unit_keywords: Array
) -> Dictionary:
	"""Try moving all models by move_vector for a fall-back. Unlike normal movement,
	fall-back REQUIRES that every model ends OUTSIDE engagement range of all enemies.
	Returns model_id -> [x, y] destinations, or empty dict if any model cannot be placed."""
	var destinations = {}
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

		# Check movement cap
		var orig_pos = original_positions.get(model_id, model_pos)
		if orig_pos.distance_to(dest) > move_cap_px + 1.0:  # +1 tolerance
			return {}

		# CRITICAL: Fall-back models MUST end outside engagement range
		if _is_position_near_enemy(dest, enemies, unit):
			# Try small offsets perpendicular to the move direction to escape ER
			var resolved = _resolve_fall_back_position(
				dest, move_vector, base_mm, base_type, base_dimensions,
				deployed_models + placed_models, enemies, unit,
				orig_pos, move_cap_px
			)
			if resolved == Vector2.INF:
				return {}  # Cannot escape ER with this direction
			dest = resolved

		# Check terrain blocking
		if _path_blocked_by_terrain(model_pos, dest, unit_keywords, terrain_features):
			return {}

		# Check overlap with deployed models and already-placed models
		var all_obstacles = deployed_models + placed_models
		if _position_collides_with_deployed(dest, base_mm, all_obstacles, 4.0, base_type, base_dimensions):
			var resolved = _resolve_fall_back_position(
				dest, move_vector, base_mm, base_type, base_dimensions,
				all_obstacles, enemies, unit, orig_pos, move_cap_px
			)
			if resolved == Vector2.INF:
				return {}
			dest = resolved

		destinations[model_id] = [dest.x, dest.y]
		placed_models.append({
			"position": dest,
			"base_mm": base_mm,
			"base_type": base_type,
			"base_dimensions": base_dimensions
		})

	return destinations

static func _resolve_fall_back_position(
	dest: Vector2, move_vector: Vector2, base_mm: int,
	base_type: String, base_dimensions: Dictionary,
	obstacles: Array, enemies: Dictionary, unit: Dictionary,
	original_pos: Vector2, move_cap_px: float
) -> Vector2:
	"""Try perpendicular and diagonal offsets to find a valid fall-back position
	that is outside engagement range and doesn't collide with other models."""
	var perp = Vector2(-move_vector.y, move_vector.x).normalized()
	if perp == Vector2.ZERO:
		# move_vector is zero, try cardinal directions
		perp = Vector2(1, 0)
	var base_radius = _model_bounding_radius_px(base_mm, base_type, base_dimensions)
	# Try wider range of offsets for fall-back (more aggressive positioning)
	var offsets = [1.0, -1.0, 2.0, -2.0, 3.0, -3.0, 4.0, -4.0]

	for multiplier in offsets:
		var offset = perp * base_radius * multiplier
		var candidate = dest + offset

		# Check board bounds
		if candidate.x < BASE_MARGIN_PX or candidate.x > BOARD_WIDTH_PX - BASE_MARGIN_PX:
			continue
		if candidate.y < BASE_MARGIN_PX or candidate.y > BOARD_HEIGHT_PX - BASE_MARGIN_PX:
			continue

		# Check movement cap
		if original_pos != Vector2.INF and move_cap_px > 0.0:
			if original_pos.distance_to(candidate) > move_cap_px + 1.0:
				continue

		# Must be outside engagement range
		if _is_position_near_enemy(candidate, enemies, unit):
			continue

		# Must not collide with other models
		if _position_collides_with_deployed(candidate, base_mm, obstacles, 4.0, base_type, base_dimensions):
			continue

		return candidate

	return Vector2.INF  # No valid position found

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

	# --- AI-GAP-4: Check for Advance and X abilities ---
	# If the unit can advance and still shoot/charge, advancing has no downside
	var unit_id = unit.get("id", "")
	# Note: we check flags directly since leader bonuses should already be applied
	# by UnitAbilityManager during the movement phase
	var adv_and_shoot = unit.get("flags", {}).get("effect_advance_and_shoot", false)
	var adv_and_charge = unit.get("flags", {}).get("effect_advance_and_charge", false)

	# Also check via description-based detection for broader coverage
	if not adv_and_shoot:
		adv_and_shoot = AIAbilityAnalyzerData.unit_has_ability_containing(unit, "advance") and AIAbilityAnalyzerData.unit_has_ability_containing(unit, "shoot")
	if not adv_and_charge:
		adv_and_charge = AIAbilityAnalyzerData.unit_has_ability_containing(unit, "advance") and AIAbilityAnalyzerData.unit_has_ability_containing(unit, "charge")

	if adv_and_shoot:
		print("AIDecisionMaker: %s has Advance and Shoot — advancing has no shooting penalty" % unit.get("meta", {}).get("name", unit_id))
		return true  # No downside to advancing

	if adv_and_charge:
		print("AIDecisionMaker: %s has Advance and Charge — advancing allows charge" % unit.get("meta", {}).get("name", unit_id))
		return true  # Can still charge after advancing

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

static func _get_weapon_range_inches(weapon: Dictionary) -> float:
	"""Parse a weapon's range field and return the range in inches. Returns 0.0 for melee or invalid."""
	var range_str = str(weapon.get("range", "0"))
	if range_str.to_lower() == "melee":
		return 0.0
	# Handle strings like "24", "36", "12" etc.
	# Also strip trailing quote mark if present (e.g. '24"')
	range_str = range_str.replace("\"", "").strip_edges()
	if range_str.is_valid_float():
		return float(range_str)
	elif range_str.is_valid_int():
		return float(int(range_str))
	return 0.0

# =============================================================================
# SHOOTING RANGE CONSIDERATION FOR MOVEMENT (MOV-1)
# =============================================================================

static func _get_enemies_in_weapon_range(centroid: Vector2, max_weapon_range: float, enemies: Dictionary) -> Array:
	"""Return array of {enemy_id, enemy_centroid, distance_inches} for enemies within weapon range."""
	var in_range = []
	if max_weapon_range <= 0.0:
		return in_range
	var range_px = max_weapon_range * PIXELS_PER_INCH
	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		var enemy_centroid = _get_unit_centroid(enemy)
		if enemy_centroid == Vector2.INF:
			continue
		var dist = centroid.distance_to(enemy_centroid)
		if dist <= range_px:
			in_range.append({
				"enemy_id": enemy_id,
				"enemy_centroid": enemy_centroid,
				"distance_inches": dist / PIXELS_PER_INCH
			})
	return in_range

static func _clamp_move_for_weapon_range(
	centroid: Vector2, move_vector: Vector2, max_weapon_range: float,
	enemies: Dictionary, unit_name: String
) -> Vector2:
	"""
	Clamp a movement vector so the unit stays within weapon range of the nearest
	enemy it can currently shoot. Returns the (possibly shortened) move vector.
	If no clamping is needed, returns the original vector.
	"""
	if max_weapon_range <= 0.0:
		return move_vector  # No ranged weapons, no constraint

	var range_px = max_weapon_range * PIXELS_PER_INCH
	var proposed_pos = centroid + move_vector

	# Find all enemies currently in range
	var enemies_in_range = _get_enemies_in_weapon_range(centroid, max_weapon_range, enemies)
	if enemies_in_range.is_empty():
		return move_vector  # No enemies in range currently, move freely

	# Check if the proposed destination keeps at least one current target in range
	var keeps_any_target = false
	for entry in enemies_in_range:
		if proposed_pos.distance_to(entry.enemy_centroid) <= range_px:
			keeps_any_target = true
			break

	if keeps_any_target:
		return move_vector  # Movement is fine, at least one target stays in range

	# The move would lose all current targets. Clamp the movement.
	# Find the nearest enemy that is currently in range
	var nearest_enemy_pos = Vector2.INF
	var nearest_dist = INF
	for entry in enemies_in_range:
		var d = centroid.distance_to(entry.enemy_centroid)
		if d < nearest_dist:
			nearest_dist = d
			nearest_enemy_pos = entry.enemy_centroid

	if nearest_enemy_pos == Vector2.INF:
		return move_vector  # Shouldn't happen, but safety fallback

	# Binary search for the maximum fraction of the move that keeps us in range
	var low = 0.0
	var high = 1.0
	var best_fraction = 0.0

	for _i in range(8):  # 8 iterations gives ~0.4% precision
		var mid = (low + high) / 2.0
		var test_pos = centroid + move_vector * mid
		if test_pos.distance_to(nearest_enemy_pos) <= range_px:
			best_fraction = mid
			low = mid
		else:
			high = mid

	if best_fraction <= 0.05:
		# Can barely move at all without losing range — stay put
		print("AIDecisionMaker: %s would lose all shooting targets — clamping to zero movement" % unit_name)
		return Vector2.ZERO

	var clamped = move_vector * best_fraction
	print("AIDecisionMaker: %s movement clamped to %.0f%% to stay within %.0f\" weapon range of nearest enemy" % [
		unit_name, best_fraction * 100.0, max_weapon_range])
	return clamped

static func _should_hold_for_shooting(
	unit: Dictionary, centroid: Vector2, target_pos: Vector2,
	max_weapon_range: float, enemies: Dictionary, move_inches: float,
	assignment: Dictionary
) -> bool:
	"""
	Determine if a ranged unit should remain stationary to maintain shooting
	rather than moving toward a distant objective. Returns true if the unit
	should hold for shooting.
	"""
	if max_weapon_range <= 0.0:
		return false  # No ranged weapons

	# Check if there are enemies currently in weapon range
	var enemies_in_range = _get_enemies_in_weapon_range(centroid, max_weapon_range, enemies)
	if enemies_in_range.is_empty():
		return false  # No targets to shoot, move freely

	# If the objective is close enough to reach this turn, move toward it
	# (being on the objective is usually more important than one turn of shooting)
	var dist_to_obj = centroid.distance_to(target_pos) if target_pos != Vector2.INF else INF
	var dist_to_obj_inches = dist_to_obj / PIXELS_PER_INCH
	if dist_to_obj_inches <= move_inches:
		return false  # Can reach objective this turn, do it

	# If the objective is high-priority (contested, uncontrolled, or needs OC),
	# and we can reach it in 2 turns, don't hold just for shooting
	var obj_priority = assignment.get("score", 0.0)
	var turns_to_reach = max(1.0, ceil(dist_to_obj_inches / move_inches)) if move_inches > 0 else 99.0
	if obj_priority >= 10.0 and turns_to_reach <= 2:
		return false  # High priority objective close enough, keep moving

	# Check if moving toward the objective would take us out of range of all targets
	var direction = (target_pos - centroid).normalized() if target_pos != Vector2.INF else Vector2.ZERO
	var move_vector = direction * move_inches * PIXELS_PER_INCH
	var proposed_pos = centroid + move_vector
	var range_px = max_weapon_range * PIXELS_PER_INCH

	var keeps_any_target = false
	for entry in enemies_in_range:
		if proposed_pos.distance_to(entry.enemy_centroid) <= range_px:
			keeps_any_target = true
			break

	if keeps_any_target:
		return false  # Moving keeps targets in range, go ahead

	# Moving would lose all targets and objective isn't reachable this turn
	# Prefer staying and shooting
	print("AIDecisionMaker: %s has %d enemies in weapon range (max %.0f\") — holding for shooting rather than moving to distant objective (%.1f\" away, %d turns)" % [
		unit.get("meta", {}).get("name", "unit"), enemies_in_range.size(), max_weapon_range,
		dist_to_obj_inches, int(turns_to_reach)])
	return true

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
	move_inches: float, snapshot: Dictionary, enemies: Dictionary,
	max_weapon_range: float = 0.0, threat_data: Array = [], objectives: Array = []
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

	# --- MOV-1: Clamp movement to maintain weapon range on current targets ---
	if max_weapon_range > 0.0:
		var unit_name = unit.get("meta", {}).get("name", unit_id)
		final_move_vector = _clamp_move_for_weapon_range(
			centroid, final_move_vector, max_weapon_range, enemies, unit_name
		)
		if final_move_vector == Vector2.ZERO:
			# Movement was clamped to zero — no valid move that keeps targets in range
			return {}

	# --- AI-TACTIC-4: Threat-aware position adjustment ---
	# If the destination would place us in a significantly more dangerous position,
	# try to find a safer alternative that still makes progress
	if not threat_data.is_empty():
		var desired_dest = centroid + final_move_vector
		var safer_dest = _find_safer_position(centroid, desired_dest, move_px, threat_data, unit, objectives)
		if safer_dest != desired_dest:
			final_move_vector = safer_dest - centroid

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

static func _get_deployed_models_split(snapshot: Dictionary, exclude_unit_id: String, unit_owner: int) -> Dictionary:
	"""Returns deployed models split by allegiance for pile-in/consolidation collision detection.
	Returns {"friendly": Array, "enemy": Array} where each entry has position, base_mm, etc."""
	var friendly = []
	var enemy = []
	for uid in snapshot.get("units", {}):
		if uid == exclude_unit_id:
			continue
		var u = snapshot.units[uid]
		var status = u.get("status", 0)
		if status == GameStateData.UnitStatus.UNDEPLOYED or status == GameStateData.UnitStatus.IN_RESERVES:
			continue
		var is_friendly = int(u.get("owner", 0)) == unit_owner
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
			var entry = {
				"position": pos,
				"base_mm": model.get("base_mm", 32),
				"base_type": model.get("base_type", "circular"),
				"base_dimensions": model.get("base_dimensions", {}),
				"rotation": model.get("rotation", 0.0)
			}
			if is_friendly:
				friendly.append(entry)
			else:
				enemy.append(entry)
	return {"friendly": friendly, "enemy": enemy}

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

	# Step 4.5: Consider GRENADE stratagem before regular shooting
	# Evaluate once per shooting phase — if worthwhile, use it before regular shooting
	if action_types.has("SELECT_SHOOTER") and not _grenade_evaluated:
		_grenade_evaluated = true
		var grenade_eval = evaluate_grenade_usage(snapshot, player)
		if grenade_eval.get("should_use", false):
			print("AIDecisionMaker: Using GRENADE stratagem — %s" % grenade_eval.get("description", ""))
			return {
				"type": "USE_GRENADE_STRATAGEM",
				"grenade_unit_id": grenade_eval.grenade_unit_id,
				"target_unit_id": grenade_eval.target_unit_id,
				"player": player,
				"_ai_description": grenade_eval.description
			}

	# Step 5: Use the SHOOT action for a full shooting sequence
	# This is the cleanest path - select + assign + confirm in one action
	if action_types.has("SELECT_SHOOTER"):
		# Build focus fire plan if not already built for this shooting phase.
		# The plan coordinates weapon assignments across ALL shooting units to
		# concentrate fire on kill thresholds rather than spreading damage.
		if not _focus_fire_plan_built:
			var shooter_unit_ids = []
			for sa in action_types["SELECT_SHOOTER"]:
				var sid = sa.get("actor_unit_id", sa.get("unit_id", ""))
				if sid != "":
					shooter_unit_ids.append(sid)
			_focus_fire_plan = _build_focus_fire_plan(snapshot, shooter_unit_ids, player)
			_focus_fire_plan_built = true
			print("AIDecisionMaker: Built focus fire plan for %d units, %d target assignments" % [
				shooter_unit_ids.size(), _focus_fire_plan.size()])
			for ff_uid in _focus_fire_plan:
				var ff_unit = snapshot.get("units", {}).get(ff_uid, {})
				var ff_name = ff_unit.get("meta", {}).get("name", ff_uid)
				var ff_assignments = _focus_fire_plan[ff_uid]
				var ff_targets = {}
				for ff_a in ff_assignments:
					var ff_tid = ff_a.get("target_unit_id", "")
					if not ff_targets.has(ff_tid):
						ff_targets[ff_tid] = 0
					ff_targets[ff_tid] += 1
				for ff_tid in ff_targets:
					var ff_target = snapshot.get("units", {}).get(ff_tid, {})
					var ff_tname = ff_target.get("meta", {}).get("name", ff_tid)
					print("  Focus fire: %s -> %s (%d weapon(s))" % [ff_name, ff_tname, ff_targets[ff_tid]])

		# Pick the first available shooter that has a plan
		var selected_unit_id = ""
		for sa in action_types["SELECT_SHOOTER"]:
			var sid = sa.get("actor_unit_id", sa.get("unit_id", ""))
			if sid != "" and _focus_fire_plan.has(sid):
				selected_unit_id = sid
				break

		# If no unit has a plan, try first available shooter with fallback scoring
		if selected_unit_id == "":
			for sa in action_types["SELECT_SHOOTER"]:
				var sid = sa.get("actor_unit_id", sa.get("unit_id", ""))
				if sid != "":
					selected_unit_id = sid
					break

		if selected_unit_id == "":
			_focus_fire_plan_built = false
			_focus_fire_plan.clear()
			return {"type": "END_SHOOTING", "_ai_description": "End Shooting Phase"}

		var unit = snapshot.get("units", {}).get(selected_unit_id, {})
		var unit_name = unit.get("meta", {}).get("name", selected_unit_id)

		# Get weapons for this unit
		var weapons = unit.get("meta", {}).get("weapons", [])
		var ranged_weapons = []
		for w in weapons:
			if w.get("type", "").to_lower() == "ranged":
				ranged_weapons.append(w)

		if ranged_weapons.is_empty():
			# Remove from plan and skip
			_focus_fire_plan.erase(selected_unit_id)
			return {
				"type": "SKIP_UNIT",
				"actor_unit_id": selected_unit_id,
				"_ai_description": "Skipped %s — no ranged weapons" % unit_name
			}

		var enemies = _get_enemy_units(snapshot, player)
		if enemies.is_empty():
			_focus_fire_plan_built = false
			_focus_fire_plan.clear()
			return {"type": "END_SHOOTING", "_ai_description": "End Shooting Phase (no targets)"}

		# Use focus fire plan assignments if available for this unit
		var assignments = []
		if _focus_fire_plan.has(selected_unit_id):
			assignments = _focus_fire_plan[selected_unit_id]
			_focus_fire_plan.erase(selected_unit_id)
			# Filter out assignments targeting units that may have been destroyed by earlier shooters
			var valid_assignments = []
			for a in assignments:
				var tid = a.get("target_unit_id", "")
				if enemies.has(tid):
					valid_assignments.append(a)
				else:
					print("AIDecisionMaker: Dropping assignment for destroyed target %s" % tid)
			assignments = valid_assignments
			# If all plan targets were destroyed, fall back to greedy scoring
			if assignments.is_empty() and not enemies.is_empty():
				assignments = _build_unit_assignments_fallback(unit, ranged_weapons, enemies, snapshot)
				print("AIDecisionMaker: Plan targets destroyed, using fallback for %s (%d assignments)" % [unit_name, assignments.size()])
			else:
				print("AIDecisionMaker: Using focus fire plan for %s (%d assignments)" % [unit_name, assignments.size()])
		else:
			# Fallback: per-weapon greedy scoring (same as old behavior)
			assignments = _build_unit_assignments_fallback(unit, ranged_weapons, enemies, snapshot)
			print("AIDecisionMaker: Using fallback scoring for %s (%d assignments)" % [unit_name, assignments.size()])

		if assignments.is_empty():
			return {
				"type": "SKIP_UNIT",
				"actor_unit_id": selected_unit_id,
				"_ai_description": "Skipped %s — no valid targets in range" % unit_name
			}

		# Build target summary for description
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
			"actor_unit_id": selected_unit_id,
			"payload": {
				"assignments": assignments
			},
			"_ai_description": "%s shoots at %s (%d weapon(s), focus fire)" % [unit_name, target_summary, assignments.size()]
		}

	# No shooters left, end phase — reset plan cache
	_focus_fire_plan_built = false
	_focus_fire_plan.clear()
	return {"type": "END_SHOOTING", "_ai_description": "End Shooting Phase"}

# =============================================================================
# FOCUS FIRE PLAN BUILDER
# =============================================================================

static func _build_focus_fire_plan(snapshot: Dictionary, shooter_unit_ids: Array, player: int) -> Dictionary:
	"""
	Build a coordinated shooting plan across all shooting units.
	Returns {unit_id: [{weapon_id, target_unit_id, model_ids}]} mapping.

	Algorithm:
	1. Calculate kill threshold (total remaining wounds) for each enemy
	2. For each weapon on each shooter, estimate expected damage against each enemy
	3. Score each enemy by: can we kill it? threat level? expected damage efficiency?
	4. Greedily allocate weapons to targets, prioritizing kill thresholds
	5. Redirect excess damage to secondary targets
	"""
	var enemies = _get_enemy_units(snapshot, player)
	if enemies.is_empty():
		return {}

	# --- Step 1: Build weapon inventory across all shooters ---
	# Each entry: {unit_id, weapon, weapon_id, unit}
	var all_weapons = []
	for unit_id in shooter_unit_ids:
		var unit = snapshot.get("units", {}).get(unit_id, {})
		if unit.is_empty():
			continue
		var weapons = unit.get("meta", {}).get("weapons", [])
		for w in weapons:
			if w.get("type", "").to_lower() != "ranged":
				continue
			var weapon_name = w.get("name", "")
			var weapon_id = _generate_weapon_id(weapon_name, w.get("type", ""))

			# ONE SHOT: Skip one-shot weapons that have been fully fired
			var _re1 = _rules_engine()
			if _re1 and _re1.is_one_shot_weapon(weapon_id, snapshot):
				var all_fired = true
				var models = unit.get("models", [])
				for model in models:
					if model.get("alive", true):
						var model_id = model.get("id", "")
						if not _re1.has_fired_one_shot(unit, model_id, weapon_id):
							all_fired = false
							break
				if all_fired:
					continue

			all_weapons.append({
				"unit_id": unit_id,
				"weapon": w,
				"weapon_id": weapon_id,
				"unit": unit
			})

	if all_weapons.is_empty():
		return {}

	# --- Step 2: Calculate kill thresholds and expected damage matrix ---
	# kill_threshold[enemy_id] = total remaining wounds across all alive models
	var kill_thresholds = {}
	# target_value[enemy_id] = priority score for killing this target
	var target_values = {}

	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		kill_thresholds[enemy_id] = _calculate_kill_threshold(enemy)
		target_values[enemy_id] = _calculate_target_value(enemy, snapshot, player)

	# damage_matrix[weapon_index][enemy_id] = expected damage
	var damage_matrix = []
	for wi in range(all_weapons.size()):
		var weapon_entry = all_weapons[wi]
		var weapon = weapon_entry["weapon"]
		var shooter_unit = weapon_entry["unit"]
		var dmg_row = {}
		for enemy_id in enemies:
			var enemy = enemies[enemy_id]
			var dmg = _estimate_weapon_damage(weapon, enemy, snapshot, shooter_unit)
			dmg_row[enemy_id] = dmg
		damage_matrix.append(dmg_row)

	# --- Step 3: Greedy allocation (T7-6 enhanced) ---
	# Track how much expected damage is already allocated to each target
	var allocated_damage = {}
	for enemy_id in enemies:
		allocated_damage[enemy_id] = 0.0

	# Track which weapon has been assigned: weapon_assignments[wi] = target_id or ""
	var weapon_target = []
	for wi in range(all_weapons.size()):
		weapon_target.append("")

	# T7-6: Sort targets by value-per-threshold (efficiency of kill).
	# Targets that give the best value for the least damage required should be
	# prioritised — killing a cheap 2HP target first frees weapons for others.
	var sorted_targets = enemies.keys()
	sorted_targets.sort_custom(func(a, b):
		var thresh_a = kill_thresholds.get(a, 1.0)
		var thresh_b = kill_thresholds.get(b, 1.0)
		var ratio_a = target_values.get(a, 0) / maxf(thresh_a, 0.1)
		var ratio_b = target_values.get(b, 0) / maxf(thresh_b, 0.1)
		# Break ties with raw value (higher value first)
		if absf(ratio_a - ratio_b) < 0.001:
			return target_values.get(a, 0) > target_values.get(b, 0)
		return ratio_a > ratio_b
	)

	# T7-6: Calculate model-level kill thresholds (wounds to kill N models)
	# Used for partial kill assessment when we can't wipe the whole unit
	var model_wounds_map = {}  # enemy_id -> wounds per model
	for enemy_id in enemies:
		model_wounds_map[enemy_id] = float(_get_target_wounds_per_model(enemies[enemy_id]))

	# Pass 1: For each high-value target, assign enough weapons to reach kill threshold
	for enemy_id in sorted_targets:
		var threshold = kill_thresholds[enemy_id]
		if threshold <= 0:
			continue

		# Gather weapons that can damage this target, with efficiency info
		var candidates = []  # [{weapon_index, damage, efficiency}]
		for wi in range(all_weapons.size()):
			if weapon_target[wi] != "":
				continue  # Already assigned
			var dmg = damage_matrix[wi].get(enemy_id, 0.0)
			if dmg <= 0:
				continue  # Can't hit this target (out of range, etc.)
			var eff = _calculate_efficiency_multiplier(all_weapons[wi]["weapon"], enemies[enemy_id])
			candidates.append({"wi": wi, "damage": dmg, "efficiency": eff})

		if candidates.is_empty():
			continue

		# Sort by damage descending (assign most effective weapons first)
		candidates.sort_custom(func(a, b): return a["damage"] > b["damage"])

		# Calculate total potential damage against this target
		var total_potential = 0.0
		for c in candidates:
			total_potential += c["damage"]

		# T7-6: Also compute well-matched damage (efficiency >= neutral) for
		# partial kill assessment. Don't drag poorly-matched weapons into partial kills.
		var well_matched_potential = 0.0
		var well_matched_candidates = []
		for c in candidates:
			if c["efficiency"] >= EFFICIENCY_NEUTRAL:
				well_matched_potential += c["damage"]
				well_matched_candidates.append(c)

		var alive_count = _get_alive_models(enemies[enemy_id]).size()
		var total_count = enemies[enemy_id].get("models", []).size()
		var below_half = total_count > 0 and alive_count * 2 < total_count

		# T7-6: Enhanced kill assessment with model-level partial kills.
		# For full wipe assessment, use all weapons. For partial kills, only count
		# well-matched weapons to avoid misallocating (e.g. lascannon vs hordes).
		var can_wipe = total_potential >= threshold * 0.6
		var wpm = model_wounds_map.get(enemy_id, 1.0)
		var matched_model_kills = floorf(well_matched_potential / maxf(wpm, 0.1)) if wpm > 0 else 0.0
		var worth_partial_kill = alive_count > 1 and matched_model_kills >= 1.0

		if not can_wipe and not below_half and not worth_partial_kill:
			continue  # Not worth focusing on — will be handled in pass 2

		# Determine target budget and which weapons to draw from:
		# - If we can wipe or below half: use ALL weapons up to kill threshold
		# - If partial kill: only use well-matched weapons
		var target_budget: float
		var assign_candidates: Array
		if can_wipe or below_half:
			target_budget = threshold * OVERKILL_TOLERANCE
			assign_candidates = candidates
		else:
			# Partial kill: use only well-matched weapons
			var target_model_kills = min(matched_model_kills, float(alive_count))
			target_budget = target_model_kills * wpm * OVERKILL_TOLERANCE
			target_budget = min(target_budget, threshold * OVERKILL_TOLERANCE)
			assign_candidates = well_matched_candidates

		for c in assign_candidates:
			if allocated_damage[enemy_id] >= target_budget:
				break  # Enough damage allocated
			# T7-6: Once we've passed the actual kill threshold, don't pull in
			# poorly-matched weapons — let them find better targets in Pass 2.
			if allocated_damage[enemy_id] >= threshold and c["efficiency"] < EFFICIENCY_NEUTRAL:
				continue
			var wi = c["wi"]
			weapon_target[wi] = enemy_id
			allocated_damage[enemy_id] += c["damage"]

	# Pass 2: Coordinated secondary target allocation (T7-6 enhanced).
	# Instead of assigning each remaining weapon independently, group remaining
	# weapons to reach kill thresholds on secondary targets too.
	var remaining_weapons = []  # indices of unassigned weapons
	for wi in range(all_weapons.size()):
		if weapon_target[wi] == "":
			remaining_weapons.append(wi)

	if not remaining_weapons.is_empty():
		# Build secondary targets: enemies that still have remaining health after Pass 1
		var secondary_targets = []
		for enemy_id in sorted_targets:
			var threshold = kill_thresholds.get(enemy_id, 0)
			if threshold <= 0:
				continue
			# How much more damage needed to reach the kill threshold?
			var remaining_hp = threshold - allocated_damage.get(enemy_id, 0.0)
			if remaining_hp <= 0:
				continue  # Already allocated enough
			secondary_targets.append(enemy_id)

		# For each secondary target, try to coordinate remaining weapons
		for enemy_id in secondary_targets:
			if remaining_weapons.is_empty():
				break

			var threshold = kill_thresholds.get(enemy_id, 0)
			var remaining_hp = threshold - allocated_damage.get(enemy_id, 0.0)
			var wpm = model_wounds_map.get(enemy_id, 1.0)

			# Gather remaining weapons that can damage this target
			var sec_candidates = []
			for wi in remaining_weapons:
				var dmg = damage_matrix[wi].get(enemy_id, 0.0)
				if dmg > 0:
					sec_candidates.append({"wi": wi, "damage": dmg})

			if sec_candidates.is_empty():
				continue

			sec_candidates.sort_custom(func(a, b): return a["damage"] > b["damage"])

			# Calculate if remaining weapons can reach a meaningful kill count
			var sec_total = 0.0
			for c in sec_candidates:
				sec_total += c["damage"]

			var can_contribute_kill = sec_total >= wpm  # Can kill at least 1 model
			if not can_contribute_kill:
				continue  # Not enough remaining firepower to kill even 1 model

			# Allocate remaining weapons to this secondary target
			var sec_budget = min(remaining_hp, threshold) * OVERKILL_TOLERANCE
			for c in sec_candidates:
				if allocated_damage.get(enemy_id, 0.0) >= threshold * OVERKILL_TOLERANCE:
					break
				if allocated_damage.get(enemy_id, 0.0) - (threshold - remaining_hp) >= sec_budget:
					break
				var wi = c["wi"]
				weapon_target[wi] = enemy_id
				allocated_damage[enemy_id] += c["damage"]
				remaining_weapons.erase(wi)

		# Pass 2b: Any still-unassigned weapons get their best individual target
		for wi in remaining_weapons:
			var best_target_id = ""
			var best_score = -1.0

			for enemy_id in enemies:
				var dmg = damage_matrix[wi].get(enemy_id, 0.0)
				if dmg <= 0:
					continue

				# Score: base damage * target value, with bonus if approaching kill threshold
				var score = dmg * target_values.get(enemy_id, 1.0)

				# Bonus: if adding this weapon helps reach the kill threshold
				var threshold = kill_thresholds.get(enemy_id, 0)
				var current_alloc = allocated_damage.get(enemy_id, 0)
				if threshold > 0 and current_alloc < threshold and current_alloc + dmg >= threshold * 0.6:
					score *= KILL_BONUS_MULTIPLIER

				# Penalty for massive overkill — redirect to less-saturated targets
				if threshold > 0 and current_alloc >= threshold * OVERKILL_TOLERANCE:
					score *= 0.3

				if score > best_score:
					best_score = score
					best_target_id = enemy_id

			if best_target_id != "":
				weapon_target[wi] = best_target_id
				allocated_damage[best_target_id] += damage_matrix[wi].get(best_target_id, 0.0)

	# --- Step 4: Build per-unit assignment dictionaries ---
	var plan = {}
	for wi in range(all_weapons.size()):
		var target_id = weapon_target[wi]
		if target_id == "":
			continue
		var weapon_entry = all_weapons[wi]
		var uid = weapon_entry["unit_id"]
		if not plan.has(uid):
			plan[uid] = []
		plan[uid].append({
			"weapon_id": weapon_entry["weapon_id"],
			"target_unit_id": target_id,
			"model_ids": _get_alive_model_ids(weapon_entry["unit"])
		})

	# Log focus fire summary with efficiency info
	for enemy_id in allocated_damage:
		var alloc = allocated_damage[enemy_id]
		if alloc > 0:
			var threshold = kill_thresholds.get(enemy_id, 0)
			var enemy = enemies[enemy_id]
			var ename = enemy.get("meta", {}).get("name", enemy_id)
			var kill_pct = (alloc / threshold * 100.0) if threshold > 0 else 0.0
			var target_type_name = _target_type_name(_classify_target_type(enemy))
			print("AIDecisionMaker: Focus fire -> %s [%s]: %.1f eff-adjusted dmg vs %.1f HP (%.0f%% kill)" % [
				ename, target_type_name, alloc, threshold, kill_pct])

	# Log weapon role assignments for debugging
	for wi in range(all_weapons.size()):
		var target_id = weapon_target[wi]
		if target_id == "":
			continue
		var weapon_entry = all_weapons[wi]
		var w = weapon_entry["weapon"]
		var wname = w.get("name", "?")
		var role_name = _weapon_role_name(_classify_weapon_role(w))
		var target = enemies.get(target_id, {})
		var tname = target.get("meta", {}).get("name", target_id)
		var eff = _calculate_efficiency_multiplier(w, target)
		print("AIDecisionMaker:   %s [%s] -> %s (efficiency: %.2f)" % [wname, role_name, tname, eff])

	return plan

static func _calculate_kill_threshold(unit: Dictionary) -> float:
	"""Calculate total remaining wounds across all alive models in a unit."""
	var total = 0.0
	for model in unit.get("models", []):
		if model.get("alive", true):
			total += float(model.get("current_wounds", model.get("wounds", 1)))
	return total

static func _calculate_target_value(target_unit: Dictionary, snapshot: Dictionary, player: int) -> float:
	"""
	Calculate a priority value for killing this target.
	Higher value = more important to kill.
	Considers: threat level, objective proximity, keywords, health status.
	"""
	var value = 1.0

	var meta = target_unit.get("meta", {})
	var stats = meta.get("stats", {})
	var keywords = meta.get("keywords", [])

	# Threat from ranged weapons (units that can shoot back are higher priority)
	var weapons = meta.get("weapons", [])
	var ranged_threat = 0.0
	for w in weapons:
		if w.get("type", "").to_lower() == "ranged":
			var attacks_str = w.get("attacks", "1")
			var attacks = float(attacks_str) if attacks_str.is_valid_float() else 1.0
			var dmg_str = w.get("damage", "1")
			var dmg = float(dmg_str) if dmg_str.is_valid_float() else 1.0
			ranged_threat += attacks * dmg
	value += ranged_threat * 0.1

	# Melee threat (units that can charge and deal damage)
	var melee_threat = 0.0
	for w in weapons:
		if w.get("type", "").to_lower() == "melee":
			var attacks_str = w.get("attacks", "1")
			var attacks = float(attacks_str) if attacks_str.is_valid_float() else 1.0
			var dmg_str = w.get("damage", "1")
			var dmg = float(dmg_str) if dmg_str.is_valid_float() else 1.0
			melee_threat += attacks * dmg
	value += melee_threat * 0.05

	# Character bonus (leaders provide buffs, losing them hurts more)
	if "CHARACTER" in keywords:
		value *= 1.3

	# Vehicle/Monster bonus (high-threat, high-wound targets)
	if "VEHICLE" in keywords or "MONSTER" in keywords:
		value *= 1.2

	# Below half health bonus (finish off wounded units)
	var alive_count = _get_alive_models(target_unit).size()
	var total_count = target_unit.get("models", []).size()
	if total_count > 0 and alive_count * 2 < total_count:
		value *= LOW_HEALTH_BONUS

	# Objective proximity bonus (units near objectives are higher priority)
	var unit_centroid = _get_unit_centroid(target_unit)
	if unit_centroid != Vector2.INF:
		var objectives = _get_objectives(snapshot)
		for obj_pos in objectives:
			var dist = unit_centroid.distance_to(obj_pos)
			if dist < OBJECTIVE_CONTROL_RANGE_PX:
				value *= 1.4  # On an objective
				break
			elif dist < OBJECTIVE_CONTROL_RANGE_PX * 2:
				value *= 1.15  # Near an objective

	# Objective Control value (high OC units on objectives are very important)
	var oc = int(stats.get("oc", 0))
	if oc >= 2:
		value += float(oc) * 0.2

	return value

static func _estimate_weapon_damage(weapon: Dictionary, target_unit: Dictionary, snapshot: Dictionary, shooter_unit: Dictionary) -> float:
	"""
	Estimate expected damage of a weapon against a target.
	Similar to _score_shooting_target but returns raw expected damage without bonuses,
	and checks range. Includes weapon keyword modifiers (SHOOT-5).
	"""
	# Range check
	var weapon_range_inches = _get_weapon_range_inches(weapon)
	var dist_inches: float = -1.0  # -1 means unknown distance
	if weapon_range_inches > 0.0 and not shooter_unit.is_empty():
		dist_inches = _get_closest_model_distance_inches(shooter_unit, target_unit)
		if dist_inches > weapon_range_inches:
			return 0.0

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
	var target_invuln = _get_target_invulnerable_save(target_unit)

	var p_hit = _hit_probability(bs)
	var p_wound = _wound_probability(strength, toughness)
	var p_unsaved = 1.0 - _save_probability(target_save, ap, target_invuln)

	# --- Apply weapon keyword modifiers (SHOOT-5) ---
	var kw_mods = _apply_weapon_keyword_modifiers(
		weapon, target_unit,
		attacks, p_hit, p_wound, p_unsaved, damage,
		strength, toughness, target_save, ap, target_invuln,
		dist_inches, weapon_range_inches
	)
	attacks = kw_mods["attacks"]
	p_hit = kw_mods["p_hit"]
	p_wound = kw_mods["p_wound"]
	p_unsaved = kw_mods["p_unsaved"]
	damage = kw_mods["damage"]

	# --- T7-6: Wound overflow cap ---
	# In 40k, damage that exceeds a model's remaining wounds is lost. Cap damage
	# at wounds-per-model to avoid overestimating kill potential (e.g. D6+1 damage
	# weapon only deals 1 effective damage per unsaved wound vs 1W models).
	var wounds_per_model = _get_target_wounds_per_model(target_unit)
	if wounds_per_model > 0:
		damage = min(damage, float(wounds_per_model))

	# Scale by number of alive models that carry this weapon
	var model_count = _get_alive_models(shooter_unit).size()
	if model_count < 1:
		model_count = 1

	var raw_damage = attacks * p_hit * p_wound * p_unsaved * damage * model_count

	# --- AI-GAP-4: Factor in target FNP for more accurate damage estimates ---
	var target_fnp = AIAbilityAnalyzerData.get_unit_fnp(target_unit)
	if target_fnp > 0:
		var fnp_multiplier = AIAbilityAnalyzerData.get_fnp_damage_multiplier(target_fnp)
		raw_damage *= fnp_multiplier

	# --- AI-GAP-4: Factor in shooter's leader ability bonuses ---
	if not shooter_unit.is_empty():
		var shooter_id = shooter_unit.get("id", "")
		if shooter_id != "":
			var all_units_for_bonus = snapshot.get("units", {})
			var offensive_mult = AIAbilityAnalyzerData.get_offensive_multiplier_ranged(shooter_id, shooter_unit, all_units_for_bonus)
			if offensive_mult > 1.0:
				raw_damage *= offensive_mult

	# Apply weapon-target efficiency multiplier to guide weapon allocation
	var efficiency = _calculate_efficiency_multiplier(weapon, target_unit)
	return raw_damage * efficiency

static func _build_unit_assignments_fallback(unit: Dictionary, ranged_weapons: Array, enemies: Dictionary, snapshot: Dictionary) -> Array:
	"""
	Fallback per-weapon greedy scoring (original behavior).
	Used when a unit is not in the focus fire plan.
	"""
	var assignments = []
	for weapon in ranged_weapons:
		var weapon_name = weapon.get("name", "")
		var weapon_id = _generate_weapon_id(weapon_name, weapon.get("type", ""))

		# ONE SHOT: Skip one-shot weapons that have been fired
		var _re2 = _rules_engine()
		if _re2 and _re2.is_one_shot_weapon(weapon_id, snapshot):
			var all_fired = true
			var models = unit.get("models", [])
			for model in models:
				if model.get("alive", true):
					var model_id = model.get("id", "")
					if not _re2.has_fired_one_shot(unit, model_id, weapon_id):
						all_fired = false
						break
			if all_fired:
				continue

		# Score each enemy target (includes weapon range check)
		var best_target_id = ""
		var best_score = -1.0
		for enemy_id in enemies:
			var enemy = enemies[enemy_id]
			var score = _score_shooting_target(weapon, enemy, snapshot, unit)
			if score > best_score:
				best_score = score
				best_target_id = enemy_id

		if best_target_id != "" and best_score > 0:
			assignments.append({
				"weapon_id": weapon_id,
				"target_unit_id": best_target_id,
				"model_ids": _get_alive_model_ids(unit)
			})
			# T7-7: Log weapon-target efficiency for fallback assignments
			var role_name = _weapon_role_name(_classify_weapon_role(weapon))
			var target = enemies.get(best_target_id, {})
			var tname = target.get("meta", {}).get("name", best_target_id)
			var target_type_name = _target_type_name(_classify_target_type(target))
			var eff = _calculate_efficiency_multiplier(weapon, target)
			print("AIDecisionMaker: Fallback assign %s [%s] -> %s [%s] (efficiency: %.2f, score: %.2f)" % [
				weapon_name, role_name, tname, target_type_name, eff, best_score])

	return assignments

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

	# Command Re-roll: Evaluate whether to reroll failed charge rolls
	# Note: ChargePhase puts USE/DECLINE in available actions. However, we lack the
	# roll context (rolled distance, required distance) here. The AIPlayer signal
	# handler (_on_command_reroll_opportunity) handles this with full context.
	# As a fallback if the signal didn't fire, decline here.
	if action_types.has("USE_COMMAND_REROLL") or action_types.has("DECLINE_COMMAND_REROLL"):
		# Default fallback: decline (signal handler should have already acted)
		var unit_id = ""
		if action_types.has("USE_COMMAND_REROLL"):
			unit_id = action_types["USE_COMMAND_REROLL"][0].get("actor_unit_id", "")
		elif action_types.has("DECLINE_COMMAND_REROLL"):
			unit_id = action_types["DECLINE_COMMAND_REROLL"][0].get("actor_unit_id", "")
		return {
			"type": "DECLINE_COMMAND_REROLL",
			"actor_unit_id": unit_id,
			"_ai_description": "Decline Command Re-roll (charge fallback)"
		}

	# Fire Overwatch: Evaluate whether to fire overwatch during opponent's charge
	if action_types.has("USE_FIRE_OVERWATCH") or action_types.has("DECLINE_FIRE_OVERWATCH"):
		var ow_actions = action_types.get("USE_FIRE_OVERWATCH", [])
		if not ow_actions.is_empty():
			# Build eligible units list from available actions
			var eligible_units = []
			var enemy_unit_id = ""
			var ow_player = player
			for ow_a in ow_actions:
				eligible_units.append({
					"unit_id": ow_a.get("actor_unit_id", ""),
					"unit_name": ow_a.get("description", "")
				})
				if enemy_unit_id == "":
					enemy_unit_id = ow_a.get("enemy_unit_id", "")
				if ow_a.has("player"):
					ow_player = ow_a.player

			var ow_decision = evaluate_fire_overwatch(ow_player, eligible_units, enemy_unit_id, snapshot)
			if ow_decision.get("type", "") == "USE_FIRE_OVERWATCH":
				ow_decision["player"] = ow_player
				return ow_decision

		# Decline overwatch
		var decline_player = player
		if action_types.has("DECLINE_FIRE_OVERWATCH"):
			decline_player = action_types["DECLINE_FIRE_OVERWATCH"][0].get("player", player)
		return {
			"type": "DECLINE_FIRE_OVERWATCH",
			"player": decline_player,
			"_ai_description": "Decline Fire Overwatch"
		}

	# Heroic Intervention: evaluate whether to counter-charge
	if action_types.has("USE_HEROIC_INTERVENTION") or action_types.has("DECLINE_HEROIC_INTERVENTION"):
		var hi_player = player
		var charging_unit_id = ""
		if action_types.has("USE_HEROIC_INTERVENTION"):
			hi_player = action_types["USE_HEROIC_INTERVENTION"][0].get("player", player)
			charging_unit_id = action_types["USE_HEROIC_INTERVENTION"][0].get("charging_unit_id", "")
		elif action_types.has("DECLINE_HEROIC_INTERVENTION"):
			hi_player = action_types["DECLINE_HEROIC_INTERVENTION"][0].get("player", player)

		var hi_decision = evaluate_heroic_intervention(hi_player, charging_unit_id, snapshot)
		if hi_decision.get("type", "") == "USE_HEROIC_INTERVENTION":
			hi_decision["player"] = hi_player
			return hi_decision
		return {
			"type": "DECLINE_HEROIC_INTERVENTION",
			"player": hi_player,
			"_ai_description": "AI declines Heroic Intervention"
		}

	# Tank Shock: evaluate whether to use it after a successful charge
	if action_types.has("USE_TANK_SHOCK") or action_types.has("DECLINE_TANK_SHOCK"):
		var ts_vehicle_id = ""
		if action_types.has("USE_TANK_SHOCK"):
			ts_vehicle_id = action_types["USE_TANK_SHOCK"][0].get("actor_unit_id", "")
		elif action_types.has("DECLINE_TANK_SHOCK"):
			ts_vehicle_id = action_types["DECLINE_TANK_SHOCK"][0].get("actor_unit_id", "")

		var ts_decision = evaluate_tank_shock(player, ts_vehicle_id, snapshot)
		return ts_decision

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

	# No good charge found (or no targets) — skip remaining chargeable units one at a time
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

		# --- AI-GAP-4: Check if charger has melee ability bonuses ---
		var all_units_charge = snapshot.get("units", {})
		var charger_melee_mult = AIAbilityAnalyzerData.get_offensive_multiplier_melee(uid, unit, all_units_charge)
		if charger_melee_mult > 1.0:
			melee_bonus *= charger_melee_mult
			print("AIDecisionMaker: %s has melee leader bonuses (mult=%.2f)" % [unit_name, charger_melee_mult])

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

	# --- AI-GAP-4: Factor in charger's melee leader bonuses ---
	var charger_id = charger.get("id", "")
	if charger_id != "":
		var all_units = snapshot.get("units", {})
		var melee_mult = AIAbilityAnalyzerData.get_offensive_multiplier_melee(charger_id, charger, all_units)
		if melee_mult > 1.0:
			score *= melee_mult

	# --- AI-GAP-4: Factor in target's defensive abilities ---
	var target_id_for_def = target.get("id", "")
	if target_id_for_def != "":
		var all_units_def = snapshot.get("units", {})
		var def_mult = AIAbilityAnalyzerData.get_defensive_multiplier(target_id_for_def, target, all_units_def)
		if def_mult > 1.0:
			# Higher defensive multiplier = harder to kill = lower score
			score /= def_mult

	return max(0.0, score)

static func _estimate_melee_damage(attacker: Dictionary, defender: Dictionary) -> float:
	"""Estimate expected damage from a melee attack using the attacker's best melee weapon."""
	var weapons = attacker.get("meta", {}).get("weapons", [])
	var best_damage = 0.0
	var alive_attackers = _get_alive_models(attacker).size()

	var target_toughness = int(defender.get("meta", {}).get("stats", {}).get("toughness", 4))
	var target_save = int(defender.get("meta", {}).get("stats", {}).get("save", 4))
	var target_invuln = _get_target_invulnerable_save(defender)

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
		var p_unsaved = 1.0 - _save_probability(target_save, ap, target_invuln)

		# Total expected damage for entire unit with this weapon
		var weapon_damage = attacks * alive_attackers * p_hit * p_wound * p_unsaved * damage
		best_damage = max(best_damage, weapon_damage)

	# Fallback: close combat weapon (S=user, AP0, D1, 1 attack)
	if best_damage == 0.0 and alive_attackers > 0:
		var charger_strength = int(attacker.get("meta", {}).get("stats", {}).get("toughness", 4))
		var p_hit = _hit_probability(4)  # WS4+ default
		var p_wound = _wound_probability(charger_strength, target_toughness)
		var p_unsaved = 1.0 - _save_probability(target_save, 0, target_invuln)
		best_damage = alive_attackers * p_hit * p_wound * p_unsaved * 1.0

	# --- AI-GAP-4: Factor in target FNP for more accurate melee damage estimates ---
	var target_fnp = AIAbilityAnalyzerData.get_unit_fnp(defender)
	if target_fnp > 0:
		var fnp_multiplier = AIAbilityAnalyzerData.get_fnp_damage_multiplier(target_fnp)
		best_damage *= fnp_multiplier

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

static func _pile_in_position_collides(pos: Vector2, base_mm: int,
		friendly_obstacles: Array, enemy_obstacles: Array, placed_positions: Array,
		base_type: String = "circular", base_dimensions: Dictionary = {}) -> bool:
	"""Check collision during pile-in/consolidation movement.
	Uses 2px gap for friendly models (prevent stacking), -1px gap for enemy models
	(allow base-to-base contact but prevent true physical overlap)."""
	if _position_collides_with_deployed(pos, base_mm, friendly_obstacles + placed_positions, 2.0, base_type, base_dimensions):
		return true
	if _position_collides_with_deployed(pos, base_mm, enemy_obstacles, -1.0, base_type, base_dimensions):
		return true
	return false

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

	# Get deployed models split by allegiance for collision checking
	# Friendly models use 2px gap (prevent stacking), enemy models use -1px gap
	# (allow base-to-base contact during pile-in)
	var obstacle_split = _get_deployed_models_split(snapshot, unit_id, unit_owner)
	var friendly_obstacles = obstacle_split.friendly
	var enemy_obstacles = obstacle_split.enemy

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
		# Friendly obstacles use 2px gap, enemy obstacles use -1px gap (allow B2B contact)
		if _pile_in_position_collides(candidate_pos, base_mm, friendly_obstacles, enemy_obstacles, placed_positions, base_type, base_dimensions):
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
					# Check collision (friendly gap=2px, enemy gap=-1px)
					if not _pile_in_position_collides(test_pos, base_mm, friendly_obstacles, enemy_obstacles, placed_positions, base_type, base_dimensions):
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
		# Enhanced consolidation: prioritise wrapping enemies and tagging new units
		movements = _compute_consolidate_movements_engagement(snapshot, unit_id, unit, player)
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

static func _compute_consolidate_movements_engagement(snapshot: Dictionary, unit_id: String, unit: Dictionary, player: int) -> Dictionary:
	"""Compute per-model consolidation destinations in engagement mode.
	Enhanced over basic pile-in with priorities:
	1. Tag new enemy units — move into ER with enemy units not currently engaged
	2. Wrap enemies — distribute models around the enemy to block fall-back
	3. Move toward closest enemy — fallback (same as pile-in)
	Maintains coherency and respects 3" movement limit.
	Returns {model_index_string: Vector2} for models that should move."""

	var movements = {}
	var alive_models = _get_alive_models_with_positions(unit)
	if alive_models.is_empty():
		return movements

	var unit_owner = int(unit.get("owner", player))
	var unit_keywords = unit.get("meta", {}).get("keywords", [])
	var has_fly = "FLY" in unit_keywords

	# Gather enemy model info grouped by unit
	var enemy_units_info = {}  # {unit_id: [{position, base_radius_px, base_mm, model_idx}]}
	var all_enemy_models_info = []  # flat list for closest-enemy lookups
	for other_unit_id in snapshot.get("units", {}):
		var other_unit = snapshot.units[other_unit_id]
		if int(other_unit.get("owner", 0)) == unit_owner:
			continue
		var other_status = other_unit.get("status", 0)
		if other_status == GameStateData.UnitStatus.UNDEPLOYED or other_status == GameStateData.UnitStatus.IN_RESERVES:
			continue
		var other_keywords = other_unit.get("meta", {}).get("keywords", [])
		if "AIRCRAFT" in other_keywords and not has_fly:
			continue
		var unit_models = []
		for em in other_unit.get("models", []):
			if not em.get("alive", true):
				continue
			var ep = _get_model_position(em)
			if ep == Vector2.INF:
				continue
			var ebr = _model_bounding_radius_px(em.get("base_mm", 32), em.get("base_type", "circular"), em.get("base_dimensions", {}))
			var info = {
				"position": ep,
				"base_radius_px": ebr,
				"base_mm": em.get("base_mm", 32),
				"enemy_unit_id": other_unit_id,
			}
			unit_models.append(info)
			all_enemy_models_info.append(info)
		if not unit_models.is_empty():
			enemy_units_info[other_unit_id] = unit_models

	if all_enemy_models_info.is_empty():
		print("AIDecisionMaker: Consolidate (engagement) for %s — no enemy models found" % unit_id)
		return movements

	# Get deployed models split for collision detection
	var obstacle_split = _get_deployed_models_split(snapshot, unit_id, unit_owner)
	var friendly_obstacles = obstacle_split.friendly
	var enemy_obstacles = obstacle_split.enemy

	var consolidate_range_px = 3.0 * PIXELS_PER_INCH
	var base_contact_threshold_px = 0.25 * PIXELS_PER_INCH

	# Track placed positions
	var placed_positions = []

	# Determine which enemy units we are ALREADY engaged with (any model in ER)
	var engaged_enemy_unit_ids = {}
	for model in alive_models:
		var mpos = _get_model_position(model)
		if mpos == Vector2.INF:
			continue
		var mbr = _model_bounding_radius_px(model.get("base_mm", 32), model.get("base_type", "circular"), model.get("base_dimensions", {}))
		for ei in all_enemy_models_info:
			var edge_dist = mpos.distance_to(ei.position) - mbr - ei.base_radius_px
			if edge_dist <= ENGAGEMENT_RANGE_PX:
				engaged_enemy_unit_ids[ei.enemy_unit_id] = true

	# Find taggable enemy units (within 4" range but NOT currently engaged)
	var taggable_enemy_units = {}  # {unit_id: [model_info]}
	for euid in enemy_units_info:
		if engaged_enemy_unit_ids.has(euid):
			continue
		# Check if any of our models can reach any model in this enemy unit (within 4")
		for model in alive_models:
			var mpos = _get_model_position(model)
			if mpos == Vector2.INF:
				continue
			var mbr = _model_bounding_radius_px(model.get("base_mm", 32), model.get("base_type", "circular"), model.get("base_dimensions", {}))
			for ei in enemy_units_info[euid]:
				var edge_dist = mpos.distance_to(ei.position) - mbr - ei.base_radius_px
				if edge_dist <= consolidate_range_px + ENGAGEMENT_RANGE_PX:
					taggable_enemy_units[euid] = enemy_units_info[euid]
					break
			if taggable_enemy_units.has(euid):
				break

	if not taggable_enemy_units.is_empty():
		print("AIDecisionMaker: Consolidate %s found %d taggable enemy unit(s)" % [unit_id, taggable_enemy_units.size()])

	# Build model entries with per-model info
	var model_entries = []
	for model in alive_models:
		var mid = model.get("id", "")
		var mpos = _get_model_position(model)
		if mpos == Vector2.INF:
			continue
		var mbr = _model_bounding_radius_px(model.get("base_mm", 32), model.get("base_type", "circular"), model.get("base_dimensions", {}))

		# Find closest enemy model
		var closest_enemy_dist_px = INF
		var closest_enemy_pos = Vector2.INF
		var closest_enemy_radius = 0.0
		var closest_enemy_unit_id = ""
		for ei in all_enemy_models_info:
			var edge_dist = mpos.distance_to(ei.position) - mbr - ei.base_radius_px
			if edge_dist < closest_enemy_dist_px:
				closest_enemy_dist_px = edge_dist
				closest_enemy_pos = ei.position
				closest_enemy_radius = ei.base_radius_px
				closest_enemy_unit_id = ei.enemy_unit_id

		# Check if this model can tag a new enemy unit (closest enemy is from unengaged unit)
		var can_tag_new = closest_enemy_unit_id != "" and taggable_enemy_units.has(closest_enemy_unit_id)

		# Also check if any taggable enemy model is within reach even if not closest
		var tag_target_pos = Vector2.INF
		var tag_target_radius = 0.0
		var tag_target_dist = INF
		if not taggable_enemy_units.is_empty() and not can_tag_new:
			for euid in taggable_enemy_units:
				for ei in taggable_enemy_units[euid]:
					var edge_dist = mpos.distance_to(ei.position) - mbr - ei.base_radius_px
					if edge_dist <= consolidate_range_px + ENGAGEMENT_RANGE_PX and edge_dist < tag_target_dist:
						tag_target_dist = edge_dist
						tag_target_pos = ei.position
						tag_target_radius = ei.base_radius_px

		model_entries.append({
			"model": model,
			"id": mid,
			"pos": mpos,
			"base_radius_px": mbr,
			"closest_enemy_dist_px": closest_enemy_dist_px,
			"closest_enemy_pos": closest_enemy_pos,
			"closest_enemy_radius": closest_enemy_radius,
			"closest_enemy_unit_id": closest_enemy_unit_id,
			"can_tag_new": can_tag_new,
			"tag_target_pos": tag_target_pos,
			"tag_target_radius": tag_target_radius,
		})

	# Sort: models closest to enemies first (they get priority for base contact),
	# but tag-capable models get higher priority
	model_entries.sort_custom(func(a, b):
		# Tag-capable models go first
		if a.can_tag_new and not b.can_tag_new:
			return true
		if b.can_tag_new and not a.can_tag_new:
			return false
		# Then by distance to closest enemy (closest first)
		return a.closest_enemy_dist_px < b.closest_enemy_dist_px
	)

	# Track which angular positions around each enemy have been claimed (for wrapping)
	var claimed_angles = {}  # {enemy_pos_key: [angle1, angle2, ...]}

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
			placed_positions.append({"position": start_pos, "base_mm": base_mm, "base_type": base_type, "base_dimensions": base_dimensions})
			continue

		# Check if model is already in base contact — hold position
		if closest_enemy_dist_px <= base_contact_threshold_px:
			print("AIDecisionMaker: Consolidate model %s already in base contact (dist=%.1fpx), holding" % [mid, closest_enemy_dist_px])
			# Record this angle as claimed for wrapping
			var angle_to_model = (start_pos - closest_enemy_pos).angle()
			var ekey = "%d_%d" % [int(closest_enemy_pos.x), int(closest_enemy_pos.y)]
			if not claimed_angles.has(ekey):
				claimed_angles[ekey] = []
			claimed_angles[ekey].append(angle_to_model)
			placed_positions.append({"position": start_pos, "base_mm": base_mm, "base_type": base_type, "base_dimensions": base_dimensions})
			continue

		# Determine target position based on priority
		var target_enemy_pos = closest_enemy_pos
		var target_enemy_radius = closest_enemy_radius
		var is_tagging = false

		# Priority 1: If this model can tag a new enemy unit (closest enemy is unengaged)
		if entry.can_tag_new:
			is_tagging = true
			print("AIDecisionMaker: Consolidate model %s targeting new enemy unit for tagging" % mid)
		elif entry.tag_target_pos != Vector2.INF:
			# Model has a reachable taggable enemy that's not its closest.
			# We still MUST move closer to the closest enemy (rules requirement),
			# but we can try a direction that angles toward the taggable target
			# while still ending closer to the closest enemy.
			pass

		# Priority 2: Wrapping — calculate a wrap position around the target enemy
		var b2b_center_dist = my_radius + target_enemy_radius
		var current_center_dist = start_pos.distance_to(target_enemy_pos)
		var can_reach_b2b = (current_center_dist - b2b_center_dist) <= consolidate_range_px

		var candidate_pos = Vector2.INF

		if can_reach_b2b:
			# Calculate wrap position: try to place on the FAR side of the enemy
			# (opposite from our approach direction — blocks enemy fall-back)
			var approach_dir = (target_enemy_pos - start_pos).normalized()
			var ekey = "%d_%d" % [int(target_enemy_pos.x), int(target_enemy_pos.y)]
			if not claimed_angles.has(ekey):
				claimed_angles[ekey] = []

			# Try angles starting from far side (180° from approach), then sweeping
			var base_angle = approach_dir.angle()
			var wrap_angles = []
			# Far side (ideal wrap position)
			wrap_angles.append(base_angle + PI)
			# Flanking positions
			wrap_angles.append(base_angle + PI * 0.75)
			wrap_angles.append(base_angle - PI * 0.75)
			wrap_angles.append(base_angle + PI * 0.5)
			wrap_angles.append(base_angle - PI * 0.5)
			wrap_angles.append(base_angle + PI * 0.25)
			wrap_angles.append(base_angle - PI * 0.25)
			# Direct approach (same as pile-in — least priority)
			wrap_angles.append(base_angle)

			for try_angle in wrap_angles:
				# Check if this angle is too close to an already-claimed angle
				var angle_taken = false
				var min_angular_gap = (my_radius + 4.0) / b2b_center_dist  # minimum gap in radians
				for claimed in claimed_angles[ekey]:
					var diff = abs(_angle_difference(try_angle, claimed))
					if diff < min_angular_gap:
						angle_taken = true
						break
				if angle_taken:
					continue

				var wrap_pos = target_enemy_pos + Vector2(cos(try_angle), sin(try_angle)) * b2b_center_dist

				# Check movement budget
				if start_pos.distance_to(wrap_pos) > consolidate_range_px:
					continue

				# Must end closer to closest enemy than we started
				if wrap_pos.distance_to(closest_enemy_pos) >= start_pos.distance_to(closest_enemy_pos):
					continue

				# Clamp to board
				wrap_pos.x = clampf(wrap_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
				wrap_pos.y = clampf(wrap_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

				# Check collision
				if not _pile_in_position_collides(wrap_pos, base_mm, friendly_obstacles, enemy_obstacles, placed_positions, base_type, base_dimensions):
					candidate_pos = wrap_pos
					claimed_angles[ekey].append(try_angle)
					if try_angle != base_angle:
						print("AIDecisionMaker: Consolidate model %s wrapping to far-side angle %.0f°" % [mid, rad_to_deg(try_angle)])
					break

		# Priority 3: Fallback — straight-line movement toward closest enemy (same as pile-in)
		if candidate_pos == Vector2.INF:
			var direction = (target_enemy_pos - start_pos).normalized()
			if direction == Vector2.ZERO:
				direction = Vector2.RIGHT

			var desired_move_dist_px = current_center_dist - b2b_center_dist
			var actual_move_dist_px = clampf(desired_move_dist_px, 0.0, consolidate_range_px)

			if actual_move_dist_px < 1.0:
				placed_positions.append({"position": start_pos, "base_mm": base_mm, "base_type": base_type, "base_dimensions": base_dimensions})
				continue

			candidate_pos = start_pos + direction * actual_move_dist_px
			candidate_pos.x = clampf(candidate_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
			candidate_pos.y = clampf(candidate_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)

			# Check collision with spiral search fallback
			if _pile_in_position_collides(candidate_pos, base_mm, friendly_obstacles, enemy_obstacles, placed_positions, base_type, base_dimensions):
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
						if start_pos.distance_to(test_pos) > consolidate_range_px:
							continue
						if test_pos.distance_to(closest_enemy_pos) >= start_pos.distance_to(closest_enemy_pos):
							continue
						test_pos.x = clampf(test_pos.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
						test_pos.y = clampf(test_pos.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
						if not _pile_in_position_collides(test_pos, base_mm, friendly_obstacles, enemy_obstacles, placed_positions, base_type, base_dimensions):
							candidate_pos = test_pos
							found_alt = true
							break
					if found_alt:
						break

				if not found_alt:
					print("AIDecisionMaker: Consolidate model %s collision — holding position" % mid)
					placed_positions.append({"position": start_pos, "base_mm": base_mm, "base_type": base_type, "base_dimensions": base_dimensions})
					continue

		# Final check: must end closer to closest enemy
		if candidate_pos.distance_to(closest_enemy_pos) >= start_pos.distance_to(closest_enemy_pos):
			print("AIDecisionMaker: Consolidate model %s would not end closer to enemy, skipping" % mid)
			placed_positions.append({"position": start_pos, "base_mm": base_mm, "base_type": base_type, "base_dimensions": base_dimensions})
			continue

		# Record the movement
		var model_index = _find_model_index_in_unit(unit, mid)
		if model_index == -1:
			print("AIDecisionMaker: Consolidate model %s index not found, skipping" % mid)
			placed_positions.append({"position": start_pos, "base_mm": base_mm, "base_type": base_type, "base_dimensions": base_dimensions})
			continue

		var move_inches = start_pos.distance_to(candidate_pos) / PIXELS_PER_INCH
		var tag_label = " (tagging new unit)" if is_tagging else ""
		print("AIDecisionMaker: Consolidate model %s (idx %d) moves %.1f\"%s toward enemy" % [mid, model_index, move_inches, tag_label])

		movements[str(model_index)] = candidate_pos
		placed_positions.append({"position": candidate_pos, "base_mm": base_mm, "base_type": base_type, "base_dimensions": base_dimensions})

	return movements

static func _angle_difference(a: float, b: float) -> float:
	"""Return the signed angular difference between two angles, normalized to [-PI, PI]."""
	var diff = fmod(a - b + PI, 2.0 * PI) - PI
	if diff < -PI:
		diff += 2.0 * PI
	return diff

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

static func _get_alive_model_ids(unit: Dictionary) -> Array:
	"""Return an array of model IDs for all alive models in the unit."""
	var ids = []
	for model in unit.get("models", []):
		if model.get("alive", true):
			ids.append(model.get("id", ""))
	return ids

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

static func _save_probability(save_val: int, ap: int, invuln: int = 0) -> float:
	var modified_save = save_val + abs(ap)
	# If the target has an invulnerable save, use whichever is better (lower)
	# Invulnerable saves ignore AP, so they are compared against the AP-modified armour save
	if invuln > 0 and invuln < modified_save:
		modified_save = invuln
	if modified_save >= 7:
		return 0.0
	if modified_save <= 1:
		return 1.0
	return (7.0 - modified_save) / 6.0

static func _get_target_invulnerable_save(target_unit: Dictionary) -> int:
	"""Get the best (lowest) invulnerable save for a target unit.
	Checks model-level invuln, unit-level meta.stats.invuln, and effect-granted invuln."""
	var best_invuln: int = 0

	# Check first alive model for native invulnerable save
	var models = target_unit.get("models", [])
	for model in models:
		if model.get("alive", true):
			var model_invuln = model.get("invuln", 0)
			if typeof(model_invuln) == TYPE_STRING:
				model_invuln = int(model_invuln) if model_invuln.is_valid_int() else 0
			if model_invuln > 0:
				best_invuln = model_invuln
			break

	# Check unit-level invuln in meta stats (fallback if models don't have it)
	if best_invuln == 0:
		var stats_invuln = target_unit.get("meta", {}).get("stats", {}).get("invuln", 0)
		if typeof(stats_invuln) == TYPE_STRING:
			stats_invuln = int(stats_invuln) if stats_invuln.is_valid_int() else 0
		if stats_invuln > 0:
			best_invuln = stats_invuln

	# Check effect-granted invulnerable save (e.g. Go to Ground stratagem)
	var effect_invuln = EffectPrimitivesData.get_effect_invuln(target_unit)
	if effect_invuln > 0:
		if best_invuln == 0 or effect_invuln < best_invuln:
			best_invuln = effect_invuln

	return best_invuln

# =============================================================================
# WEAPON KEYWORD AWARENESS (SHOOT-5)
# =============================================================================
# Adjusts expected damage calculation to account for weapon special rules:
# Blast, Rapid Fire, Melta, Anti-keyword, Torrent, Sustained Hits,
# Lethal Hits, and Devastating Wounds.
# Returns a Dictionary with adjusted values:
#   {attacks, p_hit, p_wound, p_unsaved, damage}

static func _apply_weapon_keyword_modifiers(
	weapon: Dictionary, target_unit: Dictionary,
	base_attacks: float, base_p_hit: float, base_p_wound: float,
	base_p_unsaved: float, base_damage: float,
	strength: int, toughness: int,
	target_save: int, ap: int, target_invuln: int,
	dist_inches: float, weapon_range_inches: float
) -> Dictionary:
	"""
	Apply weapon keyword modifiers to the base expected-damage components.
	All adjustments are applied as mathematical expectation modifiers
	so the AI can compare weapons fairly.
	"""
	var attacks = base_attacks
	var p_hit = base_p_hit
	var p_wound = base_p_wound
	var p_unsaved = base_p_unsaved
	var damage = base_damage
	var special_rules = weapon.get("special_rules", "").to_lower()

	# --- TORRENT: auto-hit, p_hit = 1.0 ---
	if "torrent" in special_rules:
		p_hit = 1.0

	# --- BLAST: +1 attack per 5 models in target unit (10th ed) ---
	if "blast" in special_rules:
		var alive_models = _get_alive_models(target_unit).size()
		var blast_bonus = int(alive_models / 5)
		if blast_bonus > 0:
			attacks += float(blast_bonus)

	# --- RAPID FIRE X: bonus attacks at half range ---
	var rapid_fire_val = _parse_rapid_fire_value(special_rules)
	if rapid_fire_val > 0:
		var at_half_range = _is_within_half_range(dist_inches, weapon_range_inches)
		if at_half_range == 1:
			# Definitely within half range
			attacks += float(rapid_fire_val)
		elif at_half_range == -1:
			# Definitely not within half range — no bonus
			pass
		else:
			# Unknown distance — use expected value (probability-weighted)
			attacks += float(rapid_fire_val) * HALF_RANGE_FALLBACK_PROB

	# --- MELTA X: bonus damage at half range ---
	var melta_val = _parse_melta_value(special_rules)
	if melta_val > 0:
		var at_half_range = _is_within_half_range(dist_inches, weapon_range_inches)
		if at_half_range == 1:
			damage += float(melta_val)
		elif at_half_range == -1:
			pass
		else:
			damage += float(melta_val) * HALF_RANGE_FALLBACK_PROB

	# --- ANTI-KEYWORD X+: improved wound probability vs matching targets ---
	var anti_data = _parse_anti_keyword_data(special_rules)
	var target_keywords = target_unit.get("meta", {}).get("keywords", [])
	for entry in anti_data:
		var anti_kw = entry["keyword"]  # e.g. "INFANTRY"
		var threshold = entry["threshold"]  # e.g. 4
		for tkw in target_keywords:
			if tkw.to_upper() == anti_kw:
				# Anti-keyword: critical wounds on threshold+ instead of just 6+
				# The wound probability becomes: normal wounds on non-crit + auto-wound on anti-crit
				# p_wound_anti = (1 - p_crit_anti) * base_p_wound + p_crit_anti * 1.0
				# where p_crit_anti = (7 - threshold) / 6
				var p_crit_anti = (7.0 - threshold) / 6.0
				var new_p_wound = (1.0 - p_crit_anti) * p_wound + p_crit_anti
				if new_p_wound > p_wound:
					p_wound = new_p_wound
				break  # Only apply the best matching anti-keyword

	# --- SUSTAINED HITS X: extra hits on critical hit rolls (6s) ---
	var sustained_val = _parse_sustained_hits_value(special_rules)
	if sustained_val > 0.0:
		# On a critical hit (1/6 chance per hit roll), gain sustained_val extra hits.
		# Expected extra hits per attack = CRIT_PROBABILITY * sustained_val
		# These extra hits still need to wound and get past saves.
		# Effective attack multiplier: attacks * (1 + CRIT_PROBABILITY * sustained_val * p_hit_share)
		# But since these are additional hits (not attacks), and p_hit is already factored:
		# Total effective hits = attacks * p_hit + attacks * CRIT_PROBABILITY * sustained_val
		# (critical hits are a subset of p_hit, but they generate EXTRA hits)
		# Simplification: multiply attacks by (1 + CRIT_PROBABILITY * sustained_val / p_hit) if p_hit > 0
		# More precisely: effective_hits = attacks * p_hit * (1 + CRIT_PROBABILITY / p_hit * sustained_val)
		#               = attacks * (p_hit + CRIT_PROBABILITY * sustained_val)
		# We model this as an attack multiplier so it flows through the rest of the pipeline.
		if p_hit > 0:
			var hit_multiplier = (p_hit + CRIT_PROBABILITY * sustained_val) / p_hit
			attacks *= hit_multiplier

	# --- LETHAL HITS: critical hits (6s) auto-wound ---
	if "lethal hits" in special_rules:
		# On a 6 to hit, the attack auto-wounds (skips wound roll).
		# Expected contribution from lethal hits per attack:
		#   CRIT_PROBABILITY * p_unsaved * damage (they auto-wound, so p_wound=1 for these)
		# Non-lethal hits contribute:
		#   (p_hit - CRIT_PROBABILITY) * p_wound * p_unsaved * damage
		# Total expected damage per attack:
		#   CRIT_PROBABILITY * 1.0 * p_unsaved * damage + (p_hit - CRIT_PROBABILITY) * p_wound * p_unsaved * damage
		# = p_unsaved * damage * (CRIT_PROBABILITY + (p_hit - CRIT_PROBABILITY) * p_wound)
		# We model this by adjusting p_wound to an effective value:
		if p_hit > 0:
			var effective_p_wound = (CRIT_PROBABILITY + (p_hit - CRIT_PROBABILITY) * p_wound) / p_hit
			p_wound = effective_p_wound

	# --- DEVASTATING WOUNDS: critical wounds (6s) bypass saves ---
	if "devastating wounds" in special_rules:
		# On an unmodified 6 to wound, the attack bypasses saves entirely (mortal wound).
		# Expected contribution from devastating wounds per wound:
		#   CRIT_PROBABILITY * 1.0 * damage (p_unsaved = 1.0 for these)
		# Non-devastating wounds contribute:
		#   (p_wound - CRIT_PROBABILITY) * p_unsaved * damage
		# Total = damage * (CRIT_PROBABILITY + (p_wound - CRIT_PROBABILITY) * p_unsaved)
		# Model by adjusting p_unsaved to an effective value:
		if p_wound > 0:
			var effective_p_unsaved = (CRIT_PROBABILITY + (p_wound - CRIT_PROBABILITY) * p_unsaved) / p_wound
			p_unsaved = effective_p_unsaved

	return {
		"attacks": attacks,
		"p_hit": p_hit,
		"p_wound": p_wound,
		"p_unsaved": p_unsaved,
		"damage": damage
	}

static func _is_within_half_range(dist_inches: float, weapon_range_inches: float) -> int:
	"""
	Determine if a target is within half range of a weapon.
	Returns: 1 = definitely within half range, -1 = definitely not, 0 = unknown.
	"""
	if dist_inches <= 0.0 or weapon_range_inches <= 0.0:
		return 0  # Can't determine — use fallback
	var half_range = weapon_range_inches / 2.0
	if dist_inches <= half_range:
		return 1
	else:
		return -1

static func _parse_rapid_fire_value(special_rules_lower: String) -> int:
	"""Parse 'rapid fire X' from lowercased special_rules string. Returns 0 if not found."""
	var regex = RegEx.new()
	regex.compile("rapid\\s*fire\\s*(\\d+)")
	var result = regex.search(special_rules_lower)
	if result:
		return result.get_string(1).to_int()
	return 0

static func _parse_melta_value(special_rules_lower: String) -> int:
	"""Parse 'melta X' from lowercased special_rules string. Returns 0 if not found."""
	var regex = RegEx.new()
	regex.compile("melta\\s*(\\d+)")
	var result = regex.search(special_rules_lower)
	if result:
		return result.get_string(1).to_int()
	return 0

static func _parse_anti_keyword_data(special_rules_lower: String) -> Array:
	"""Parse 'anti-X Y+' patterns from lowercased special_rules string.
	Returns Array of {keyword: String (UPPERCASE), threshold: int}."""
	var results = []
	var regex = RegEx.new()
	regex.compile("anti-(\\w+)\\s+(\\d+)\\+?")
	var matches = regex.search_all(special_rules_lower)
	for m in matches:
		results.append({
			"keyword": m.get_string(1).to_upper(),
			"threshold": m.get_string(2).to_int()
		})
	return results

static func _parse_sustained_hits_value(special_rules_lower: String) -> float:
	"""Parse 'sustained hits X' or 'sustained hits dX' from lowercased special_rules string.
	Returns the expected number of bonus hits per critical (0 if not found).
	For 'sustained hits D3', returns average of D3 = 2.0.
	For 'sustained hits D6', returns average of D6 = 3.5."""
	var regex = RegEx.new()
	regex.compile("sustained\\s*hits\\s*(d?)(\\d+)")
	var result = regex.search(special_rules_lower)
	if result:
		var is_dice = result.get_string(1) == "d"
		var val = result.get_string(2).to_int()
		if is_dice:
			# Average of dX = (X+1)/2
			if val == 3:
				return 2.0
			elif val == 6:
				return 3.5
			else:
				return (float(val) + 1.0) / 2.0
		else:
			return float(val)
	return 0.0

static func _score_shooting_target(weapon: Dictionary, target_unit: Dictionary, snapshot: Dictionary, shooter_unit: Dictionary = {}) -> float:
	# --- Range check: score 0 for out-of-range targets ---
	var weapon_range_inches = _get_weapon_range_inches(weapon)
	var dist_inches: float = -1.0  # -1 means unknown distance
	if weapon_range_inches > 0.0 and not shooter_unit.is_empty():
		dist_inches = _get_closest_model_distance_inches(shooter_unit, target_unit)
		if dist_inches > weapon_range_inches:
			return 0.0

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
	var target_invuln = _get_target_invulnerable_save(target_unit)

	var p_hit = _hit_probability(bs)
	var p_wound = _wound_probability(strength, toughness)
	var p_unsaved = 1.0 - _save_probability(target_save, ap, target_invuln)

	# --- Apply weapon keyword modifiers (SHOOT-5) ---
	var kw_mods = _apply_weapon_keyword_modifiers(
		weapon, target_unit,
		attacks, p_hit, p_wound, p_unsaved, damage,
		strength, toughness, target_save, ap, target_invuln,
		dist_inches, weapon_range_inches
	)
	attacks = kw_mods["attacks"]
	p_hit = kw_mods["p_hit"]
	p_wound = kw_mods["p_wound"]
	p_unsaved = kw_mods["p_unsaved"]
	damage = kw_mods["damage"]

	# --- T7-6: Wound overflow cap ---
	# Damage exceeding model wounds is lost in 40k. Cap for accurate scoring.
	var wounds_per_model = _get_target_wounds_per_model(target_unit)
	if wounds_per_model > 0:
		damage = min(damage, float(wounds_per_model))

	var expected_damage = attacks * p_hit * p_wound * p_unsaved * damage

	# --- AI-GAP-4: Factor in target FNP for more accurate scoring ---
	var target_fnp = AIAbilityAnalyzerData.get_unit_fnp(target_unit)
	if target_fnp > 0:
		var fnp_multiplier = AIAbilityAnalyzerData.get_fnp_damage_multiplier(target_fnp)
		expected_damage *= fnp_multiplier

	# --- AI-GAP-4: Factor in target Stealth for ranged hit penalty ---
	if AIAbilityAnalyzerData.has_stealth(target_unit):
		# Stealth imposes -1 to hit for ranged attacks; approximate as ~15% reduction
		expected_damage *= 0.85

	# Bonus: target below half strength (finish it off)
	var alive_count = _get_alive_models(target_unit).size()
	var total_count = target_unit.get("models", []).size()
	if total_count > 0 and alive_count * 2 < total_count:
		expected_damage *= 1.5

	# Bonus: target has CHARACTER keyword
	var keywords = target_unit.get("meta", {}).get("keywords", [])
	if "CHARACTER" in keywords:
		expected_damage *= 1.2

	# Apply weapon-target efficiency multiplier
	var efficiency = _calculate_efficiency_multiplier(weapon, target_unit)
	expected_damage *= efficiency

	return expected_damage

# =============================================================================
# WEAPON-TARGET EFFICIENCY MATCHING
# =============================================================================

enum WeaponRole { ANTI_TANK, ANTI_INFANTRY, GENERAL_PURPOSE }
enum TargetType { VEHICLE_MONSTER, ELITE, HORDE }

static func _classify_weapon_role(weapon: Dictionary) -> int:
	"""
	Classify a weapon as anti-tank, anti-infantry, or general purpose based on
	its strength, AP, damage, and special rules.
	"""
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
	# Handle variable damage like "D6", "D3+1", "D6+1"
	var damage = _parse_average_damage(damage_str)

	var special_rules = weapon.get("special_rules", "").to_lower()

	# Check for anti-keyword special rules first — they are the strongest indicator
	if _has_anti_vehicle_rule(special_rules):
		return WeaponRole.ANTI_TANK
	if _has_anti_infantry_rule(special_rules):
		return WeaponRole.ANTI_INFANTRY

	# Score weapon characteristics for anti-tank role
	var anti_tank_score = 0
	if strength >= ANTI_TANK_STRENGTH_THRESHOLD:
		anti_tank_score += 2
	if ap >= ANTI_TANK_AP_THRESHOLD:
		anti_tank_score += 1
	if damage >= ANTI_TANK_DAMAGE_THRESHOLD:
		anti_tank_score += 2

	# Score weapon characteristics for anti-infantry role
	var anti_infantry_score = 0
	if strength <= ANTI_INFANTRY_STRENGTH_CAP:
		anti_infantry_score += 1
	if damage <= ANTI_INFANTRY_DAMAGE_THRESHOLD:
		anti_infantry_score += 2
	if ap <= 1:
		anti_infantry_score += 1

	# Check attacks count: high attacks with low damage is anti-infantry
	var attacks_str = weapon.get("attacks", "1")
	var attacks = float(attacks_str) if attacks_str.is_valid_float() else 1.0
	if attacks >= 4 and damage <= 1.5:
		anti_infantry_score += 1

	# Blast weapons lean anti-infantry (more attacks vs larger units)
	if "blast" in special_rules:
		anti_infantry_score += 1

	# Torrent weapons are inherently anti-infantry (auto-hit, usually S4-5 D1)
	if "torrent" in special_rules:
		anti_infantry_score += 1

	# Classify based on scores
	if anti_tank_score >= 3:
		return WeaponRole.ANTI_TANK
	if anti_infantry_score >= 3:
		return WeaponRole.ANTI_INFANTRY

	return WeaponRole.GENERAL_PURPOSE

static func _classify_target_type(target_unit: Dictionary) -> int:
	"""
	Classify a target unit as vehicle/monster, elite, or horde based on
	keywords, wounds per model, and model count.
	"""
	var keywords = target_unit.get("meta", {}).get("keywords", [])
	var stats = target_unit.get("meta", {}).get("stats", {})
	var wounds_per_model = int(stats.get("wounds", 1))
	var toughness = int(stats.get("toughness", 4))
	var alive_models = _get_alive_models(target_unit)
	var model_count = alive_models.size()

	# VEHICLE or MONSTER keyword is the strongest indicator
	for kw in keywords:
		var kw_upper = kw.to_upper()
		if kw_upper == "VEHICLE" or kw_upper == "MONSTER":
			return TargetType.VEHICLE_MONSTER

	# High toughness + high wounds without explicit keyword (e.g. some big characters)
	if toughness >= 8 and wounds_per_model >= 8:
		return TargetType.VEHICLE_MONSTER

	# Horde: many models with low wounds
	if model_count >= 5 and wounds_per_model <= 1:
		return TargetType.HORDE

	# Large infantry squads with 2W are still horde-like
	if model_count >= 8 and wounds_per_model <= 2:
		return TargetType.HORDE

	# Elite: fewer, tougher models (multi-wound infantry, small squads)
	if wounds_per_model >= 2:
		return TargetType.ELITE

	# Default: small infantry squads — treat as horde-adjacent
	return TargetType.HORDE

static func _calculate_efficiency_multiplier(weapon: Dictionary, target_unit: Dictionary) -> float:
	"""
	Calculate an efficiency multiplier for matching a weapon to a target.
	Considers weapon role vs target type, damage waste on low-wound models,
	and anti-keyword special rules.
	"""
	var weapon_role = _classify_weapon_role(weapon)
	var target_type = _classify_target_type(target_unit)
	var multiplier = EFFICIENCY_NEUTRAL

	# --- Role-based matching ---
	match weapon_role:
		WeaponRole.ANTI_TANK:
			match target_type:
				TargetType.VEHICLE_MONSTER:
					multiplier = EFFICIENCY_PERFECT_MATCH
				TargetType.ELITE:
					multiplier = EFFICIENCY_GOOD_MATCH
				TargetType.HORDE:
					multiplier = EFFICIENCY_POOR_MATCH
		WeaponRole.ANTI_INFANTRY:
			match target_type:
				TargetType.HORDE:
					multiplier = EFFICIENCY_PERFECT_MATCH
				TargetType.ELITE:
					multiplier = EFFICIENCY_GOOD_MATCH
				TargetType.VEHICLE_MONSTER:
					multiplier = EFFICIENCY_POOR_MATCH
		WeaponRole.GENERAL_PURPOSE:
			multiplier = EFFICIENCY_NEUTRAL

	# --- T7-7: Damage waste penalty for multi-damage weapons on single-wound models ---
	# When a weapon's average damage exceeds 1 against single-wound targets, the
	# excess damage is wasted (each unsaved wound can only remove 1 model).
	# Wound overflow capping in _estimate_weapon_damage() handles damage ACCURACY;
	# this penalty captures the OPPORTUNITY COST — the weapon could be more effective
	# against a higher-wound target. Uses DAMAGE_WASTE_PENALTY constants.
	var avg_damage = _parse_average_damage(weapon.get("damage", "1"))
	var wpm = float(_get_target_wounds_per_model(target_unit))
	if wpm <= 1.0 and avg_damage > 1.0:
		if avg_damage >= ANTI_TANK_DAMAGE_THRESHOLD:  # D3+ avg damage (heavy waste)
			multiplier *= DAMAGE_WASTE_PENALTY_HEAVY
		else:  # D2 (moderate waste)
			multiplier *= DAMAGE_WASTE_PENALTY_MODERATE

	# --- Anti-keyword bonus ---
	var special_rules = weapon.get("special_rules", "").to_lower()
	var keywords = target_unit.get("meta", {}).get("keywords", [])

	if _weapon_anti_keyword_matches_target(special_rules, keywords):
		multiplier *= ANTI_KEYWORD_BONUS

	return multiplier

static func _get_target_wounds_per_model(target_unit: Dictionary) -> int:
	"""Get the wounds characteristic of models in the target unit."""
	var stats = target_unit.get("meta", {}).get("stats", {})
	return int(stats.get("wounds", 1))

static func _parse_average_damage(damage_str: String) -> float:
	"""
	Parse a damage string and return the average expected damage.
	Handles: "1", "2", "D3", "D6", "D3+1", "D6+1", "2D6", etc.
	"""
	if damage_str.is_valid_float():
		return float(damage_str)
	if damage_str.is_valid_int():
		return float(damage_str)

	var lower = damage_str.to_lower().strip_edges()

	# Handle "D3+N" or "D6+N" patterns
	var plus_parts = lower.split("+")
	var base_damage = 0.0
	var bonus = 0.0

	if plus_parts.size() >= 2:
		var bonus_str = plus_parts[1].strip_edges()
		bonus = float(bonus_str) if bonus_str.is_valid_float() else 0.0

	var base_str = plus_parts[0].strip_edges()

	# Handle "2D6", "2D3" etc.
	var multiplier_val = 1.0
	if base_str.find("d") > 0:
		var d_parts = base_str.split("d")
		if d_parts.size() == 2:
			var mult_str = d_parts[0].strip_edges()
			multiplier_val = float(mult_str) if mult_str.is_valid_float() else 1.0
			var die_str = d_parts[1].strip_edges()
			if die_str == "3":
				base_damage = 2.0  # Average of D3 = 2
			elif die_str == "6":
				base_damage = 3.5  # Average of D6 = 3.5
			else:
				base_damage = (float(die_str) + 1.0) / 2.0 if die_str.is_valid_float() else 1.0
	elif base_str == "d3":
		base_damage = 2.0
	elif base_str == "d6":
		base_damage = 3.5
	else:
		base_damage = float(base_str) if base_str.is_valid_float() else 1.0

	return base_damage * multiplier_val + bonus

static func _has_anti_vehicle_rule(special_rules: String) -> bool:
	"""Check if weapon special rules contain anti-vehicle or anti-monster."""
	return "anti-vehicle" in special_rules or "anti-monster" in special_rules

static func _has_anti_infantry_rule(special_rules: String) -> bool:
	"""Check if weapon special rules contain anti-infantry."""
	return "anti-infantry" in special_rules

static func _weapon_anti_keyword_matches_target(special_rules: String, target_keywords: Array) -> bool:
	"""
	Check if a weapon's anti-X keyword matches a target's keywords.
	e.g. anti-infantry 4+ matches INFANTRY targets, anti-vehicle 4+ matches VEHICLE targets.
	"""
	for kw in target_keywords:
		var kw_lower = kw.to_lower()
		# Check for "anti-<keyword>" in special rules
		var anti_pattern = "anti-" + kw_lower
		if anti_pattern in special_rules:
			return true
	return false

static func _weapon_role_name(role: int) -> String:
	"""Return a human-readable name for a weapon role."""
	match role:
		WeaponRole.ANTI_TANK:
			return "Anti-Tank"
		WeaponRole.ANTI_INFANTRY:
			return "Anti-Infantry"
		WeaponRole.GENERAL_PURPOSE:
			return "General"
		_:
			return "Unknown"

static func _target_type_name(target_type: int) -> String:
	"""Return a human-readable name for a target type."""
	match target_type:
		TargetType.VEHICLE_MONSTER:
			return "Vehicle/Monster"
		TargetType.ELITE:
			return "Elite"
		TargetType.HORDE:
			return "Horde"
		_:
			return "Unknown"

# =============================================================================
# STRATAGEM EVALUATION — AI heuristics for when to use stratagems
# =============================================================================

# --- GRENADE STRATAGEM ---

static func evaluate_grenade_usage(snapshot: Dictionary, player: int) -> Dictionary:
	"""
	Evaluate whether the AI should use the GRENADE stratagem this shooting phase.
	Returns { should_use: bool, grenade_unit_id: String, target_unit_id: String,
	          description: String } or { should_use: false }.

	Heuristic: Use Grenade when we have a GRENADES unit whose ranged weapons are
	weak (few shots, low damage) or that has no ranged weapons, AND there is an
	enemy within 8" that would take meaningful damage from 6D6 at 4+ (avg 3 MW).
	Prefer targets with many wounded low-wound models (mortal wounds bypass saves).
	"""
	var grenade_main_loop = Engine.get_main_loop()
	var strat_manager_node = null
	if grenade_main_loop and grenade_main_loop is SceneTree and grenade_main_loop.root:
		strat_manager_node = grenade_main_loop.root.get_node_or_null("/root/StratagemManager")
	if not strat_manager_node:
		return {"should_use": false}

	var eligible_units = strat_manager_node.get_grenade_eligible_units(player)
	if eligible_units.is_empty():
		return {"should_use": false}

	var best_score: float = 0.0
	var best_grenade_unit_id: String = ""
	var best_target_unit_id: String = ""
	var best_grenade_unit_name: String = ""
	var best_target_unit_name: String = ""

	for entry in eligible_units:
		var grenade_unit_id: String = entry.unit_id
		var grenade_unit = snapshot.get("units", {}).get(grenade_unit_id, {})
		if grenade_unit.is_empty():
			continue

		# Check if this unit has strong ranged weapons — if so, shooting normally is better
		var ranged_weapon_strength = _estimate_unit_ranged_strength(grenade_unit)

		# Get eligible grenade targets (within 8")
		var _re3 = _rules_engine()
		if not _re3:
			continue
		var targets = _re3.get_grenade_eligible_targets(grenade_unit_id, snapshot)
		if targets.is_empty():
			continue

		for target_info in targets:
			var target_unit_id: String = target_info.unit_id
			var target_unit = snapshot.get("units", {}).get(target_unit_id, {})
			if target_unit.is_empty():
				continue

			# Score the grenade target: mortal wounds bypass saves, so low-wound models
			# and wounded models are ideal. Average 3 MW from 6D6 at 4+.
			var target_score = _score_grenade_target(target_unit)

			# Reduce score if the unit has strong ranged weapons (shooting normally is better)
			# Grenade expected value: ~3 mortal wounds (no saves)
			# If ranged weapons do more expected damage, prefer shooting
			if ranged_weapon_strength > 4.0:
				target_score *= 0.3  # Strong ranged unit — prefer shooting
			elif ranged_weapon_strength > 2.0:
				target_score *= 0.7  # Moderate ranged unit — slight preference for shooting

			if target_score > best_score:
				best_score = target_score
				best_grenade_unit_id = grenade_unit_id
				best_target_unit_id = target_unit_id
				best_grenade_unit_name = entry.get("unit_name", grenade_unit_id)
				best_target_unit_name = target_info.get("unit_name", target_unit_id)

	# Use grenade if the score is above a meaningful threshold
	# 3 MW is expected value; score of 2.0+ means decent value
	if best_score >= 2.0 and best_grenade_unit_id != "" and best_target_unit_id != "":
		return {
			"should_use": true,
			"grenade_unit_id": best_grenade_unit_id,
			"target_unit_id": best_target_unit_id,
			"description": "%s throws GRENADE at %s" % [best_grenade_unit_name, best_target_unit_name]
		}

	return {"should_use": false}

static func _estimate_unit_ranged_strength(unit: Dictionary) -> float:
	"""
	Estimate the ranged weapon strength of a unit based on expected wounds output.
	Returns a rough score: 0 = no ranged weapons, higher = more damage output.
	"""
	var total_expected = 0.0
	var weapons = unit.get("meta", {}).get("weapons", [])
	var alive_models = _get_alive_models(unit)
	var model_count = alive_models.size()
	if model_count == 0:
		return 0.0

	for w in weapons:
		if w.get("type", "").to_lower() != "ranged":
			continue
		var attacks_str = w.get("attacks", "1")
		var attacks = float(attacks_str) if attacks_str.is_valid_float() else 1.0
		var damage_str = w.get("damage", "1")
		var avg_damage = _parse_average_damage(damage_str)
		var bs_str = w.get("bs", "4+")
		var bs = int(bs_str.replace("+", "")) if "+" in bs_str else 4
		var hit_prob = max(0.0, (7.0 - bs) / 6.0)
		# Rough wound probability (assume average target T4, moderate save)
		var wound_prob = 0.5
		var save_prob = 0.5  # Assume 50% saves get through
		total_expected += attacks * hit_prob * wound_prob * save_prob * avg_damage * model_count

	return total_expected

static func _score_grenade_target(target_unit: Dictionary) -> float:
	"""
	Score a target for GRENADE usage. Mortal wounds bypass saves, so the key
	factors are: remaining wounds (can we kill models?), model count (more models =
	more value from removing them), and unit value (characters/elites are higher value).
	"""
	var alive = _get_alive_models(target_unit)
	var alive_count = alive.size()
	if alive_count == 0:
		return 0.0

	var wounds_per_model = _get_target_wounds_per_model(target_unit)
	var avg_mortal_wounds = 3.0  # Expected from 6D6 at 4+

	# Base score: how many models can we expect to kill?
	if wounds_per_model <= 0:
		wounds_per_model = 1
	var expected_kills = avg_mortal_wounds / float(wounds_per_model)

	# Wounded models are more vulnerable — check if any models are below full wounds
	var total_remaining_wounds = 0.0
	for model in alive:
		var max_wounds = wounds_per_model
		var current_wounds = model.get("wounds", max_wounds)
		total_remaining_wounds += current_wounds

	# Score based on proportion of total wounds we'd remove
	var wound_proportion = avg_mortal_wounds / max(total_remaining_wounds, 1.0)
	var base_score = wound_proportion * 5.0  # Scale: 5.0 if we'd remove all wounds

	# Bonus for being able to finish off models (mortal wounds on 1W models = guaranteed kills)
	if wounds_per_model == 1:
		base_score += 1.0  # 3 expected kills on 1W models

	# Bonus for small elite units (killing 1-2 of 3 models is more impactful)
	if alive_count <= 3 and wounds_per_model >= 3:
		base_score += 1.0

	# Bonus for characters/high-value units
	var keywords = target_unit.get("meta", {}).get("keywords", [])
	for kw in keywords:
		if kw.to_upper() == "CHARACTER":
			base_score += 1.5
			break

	return base_score

# --- GO TO GROUND / SMOKESCREEN (Reactive — during opponent's shooting) ---

static func evaluate_reactive_stratagem(defending_player: int, available_stratagems: Array, target_unit_ids: Array, snapshot: Dictionary) -> Dictionary:
	"""
	Evaluate whether the AI should use a reactive stratagem (Go to Ground or Smokescreen)
	when being shot at. Returns the action dictionary to submit, or empty dict to decline.

	Heuristic:
	- Use Go to Ground on valuable INFANTRY targets without existing invuln saves
	- Use Smokescreen on SMOKE units being targeted (always beneficial: cover + stealth)
	- Prefer Smokescreen over Go to Ground (stealth is -1 to hit, stronger)
	- Skip if the unit is cheap/expendable (not worth 1 CP)
	"""
	var best_stratagem_id: String = ""
	var best_target_unit_id: String = ""
	var best_score: float = 0.0

	for strat_entry in available_stratagems:
		var strat = strat_entry.get("stratagem", {})
		var eligible_units = strat_entry.get("eligible_units", [])
		var strat_id = strat.get("id", "")

		for unit_id in eligible_units:
			var unit = snapshot.get("units", {}).get(unit_id, {})
			if unit.is_empty():
				continue

			var score = _score_defensive_stratagem_target(unit, strat_id)
			if score > best_score:
				best_score = score
				best_stratagem_id = strat_id
				best_target_unit_id = unit_id

	# Use the stratagem if the score is meaningful (unit is worth protecting)
	if best_score >= 1.5 and best_stratagem_id != "" and best_target_unit_id != "":
		var strat_name = ""
		for strat_entry in available_stratagems:
			if strat_entry.get("stratagem", {}).get("id", "") == best_stratagem_id:
				strat_name = strat_entry.stratagem.get("name", best_stratagem_id)
				break
		var unit_name = snapshot.get("units", {}).get(best_target_unit_id, {}).get("meta", {}).get("name", best_target_unit_id)
		return {
			"type": "USE_REACTIVE_STRATAGEM",
			"stratagem_id": best_stratagem_id,
			"target_unit_id": best_target_unit_id,
			"player": defending_player,
			"_ai_description": "AI uses %s on %s" % [strat_name, unit_name]
		}

	return {
		"type": "DECLINE_REACTIVE_STRATAGEM",
		"player": defending_player,
		"_ai_description": "AI declines reactive stratagems"
	}

static func _score_defensive_stratagem_target(unit: Dictionary, stratagem_id: String) -> float:
	"""
	Score how much a unit benefits from a defensive stratagem.
	Higher score = more worth spending 1 CP on.
	"""
	var alive = _get_alive_models(unit)
	var alive_count = alive.size()
	if alive_count == 0:
		return 0.0

	var keywords = unit.get("meta", {}).get("keywords", [])
	var stats = unit.get("meta", {}).get("stats", {})
	var wounds_per_model = int(stats.get("wounds", 1))
	var save = int(stats.get("save", 4))
	var base_score = 0.0

	# Check existing invulnerable save
	var existing_invuln = 0
	for model in alive:
		var model_invuln = model.get("invuln", 0)
		if typeof(model_invuln) == TYPE_STRING:
			model_invuln = int(model_invuln) if model_invuln.is_valid_int() else 0
		if model_invuln > 0:
			existing_invuln = model_invuln
		break
	if existing_invuln == 0:
		existing_invuln = int(stats.get("invuln", 0))

	match stratagem_id:
		"go_to_ground":
			# Go to Ground grants 6+ invuln + cover
			# More valuable when: no existing invuln, poor save, many models, high value
			if existing_invuln > 0 and existing_invuln <= 5:
				# Already has a decent invuln — 6+ invuln won't help much
				base_score += 0.5
			else:
				# No invuln or 6+ — this helps
				base_score += 1.5

			# Cover improves save by 1 (if not already in cover)
			if not unit.get("flags", {}).get("in_cover", false):
				if save >= 5:  # Poor save benefits more from cover
					base_score += 1.0
				else:
					base_score += 0.5

		"smokescreen":
			# Smokescreen grants cover + stealth (-1 to hit)
			# Stealth is always strong — it reduces incoming damage by ~17-33%
			base_score += 2.0

			# Cover on top of stealth is extra value
			if not unit.get("flags", {}).get("in_cover", false):
				base_score += 0.5

	# Scale by unit value
	# Multi-wound models are more valuable per CP
	base_score *= (1.0 + 0.1 * float(wounds_per_model * alive_count))

	# Bonus for CHARACTER units (high value)
	for kw in keywords:
		var kw_upper = kw.to_upper()
		if kw_upper == "CHARACTER":
			base_score += 1.0
		if kw_upper == "LEADER":
			base_score += 0.5

	# Penalty for single-model units with many wounds already lost
	if alive_count == 1 and wounds_per_model > 1:
		var current_wounds = alive[0].get("wounds", wounds_per_model)
		if current_wounds <= 1:
			base_score *= 0.3  # Nearly dead — not worth saving

	return base_score

# --- FIRE OVERWATCH (Reactive — during opponent's movement/charge) ---

static func evaluate_fire_overwatch(defending_player: int, eligible_units: Array, enemy_unit_id: String, snapshot: Dictionary) -> Dictionary:
	"""
	Evaluate whether the AI should use Fire Overwatch against a moving/charging enemy.
	Returns the action dictionary to submit, or empty dict to decline.

	Heuristic: Fire Overwatch hits only on unmodified 6s (16.7% hit rate).
	Use when:
	- The unit has many high-volume ranged weapons (more dice = more 6s)
	- The enemy is a high-value target (character, expensive unit)
	- The CP cost is affordable (1 CP, once per turn)
	Avoid when:
	- The unit only has 1-2 shots (very unlikely to do anything)
	- CP reserves are low (< 3 CP, save for other stratagems)
	"""
	var player_cp = _get_player_cp_from_snapshot(snapshot, defending_player)

	# Don't use overwatch if CP is low — save for more reliable stratagems
	if player_cp < 2:
		return _decline_fire_overwatch(defending_player)

	var enemy_unit = snapshot.get("units", {}).get(enemy_unit_id, {})
	if enemy_unit.is_empty():
		return _decline_fire_overwatch(defending_player)

	# Evaluate enemy threat level
	var enemy_value = _estimate_unit_value(enemy_unit)

	var best_unit_id: String = ""
	var best_unit_name: String = ""
	var best_expected_hits: float = 0.0

	for entry in eligible_units:
		var unit_id: String = ""
		var unit_name: String = ""
		if entry is Dictionary:
			unit_id = entry.get("unit_id", "")
			unit_name = entry.get("unit_name", unit_id)
		elif entry is String:
			unit_id = entry
			unit_name = entry

		var unit = snapshot.get("units", {}).get(unit_id, {})
		if unit.is_empty():
			continue

		# Count total ranged shots (overwatch hits on 6s only)
		var total_shots = _count_unit_ranged_shots(unit)
		var expected_hits = total_shots / 6.0  # 1/6 chance per shot

		if expected_hits > best_expected_hits:
			best_expected_hits = expected_hits
			best_unit_id = unit_id
			best_unit_name = unit_name

	# Use overwatch if we expect at least ~1 hit and enemy is valuable
	# Threshold: at least 0.5 expected hits (3+ total shots) AND enemy worth shooting at
	if best_expected_hits >= 0.5 and enemy_value >= 2.0 and best_unit_id != "":
		var enemy_name = enemy_unit.get("meta", {}).get("name", enemy_unit_id)
		return {
			"type": "USE_FIRE_OVERWATCH",
			"unit_id": best_unit_id,
			"player": defending_player,
			"_ai_description": "AI fires overwatch with %s at %s (%.1f expected hits)" % [best_unit_name, enemy_name, best_expected_hits]
		}

	return _decline_fire_overwatch(defending_player)

static func _decline_fire_overwatch(player: int) -> Dictionary:
	return {
		"type": "DECLINE_FIRE_OVERWATCH",
		"player": player,
		"_ai_description": "AI declines Fire Overwatch"
	}

# --- TANK SHOCK (Proactive — after own charge move with VEHICLE) ---

static func evaluate_tank_shock(player: int, vehicle_unit_id: String, snapshot: Dictionary) -> Dictionary:
	"""
	Evaluate whether the AI should use Tank Shock after a successful charge with a VEHICLE.
	Returns USE_TANK_SHOCK or DECLINE_TANK_SHOCK action dictionary.

	Heuristic: Tank Shock rolls D6 equal to Toughness (max 6), each 5+ = 1 mortal wound.
	Use when:
	- Vehicle has high toughness (T6+ → 6 dice, ~2 expected MW)
	- Enemy target has low-wound models (MW kills them outright)
	- CP is affordable (1 CP)
	Skip when:
	- Vehicle has low toughness (T4 or less → only 4 dice, ~1.3 MW)
	- CP reserves are very low (1 CP remaining)
	"""
	var player_cp = _get_player_cp_from_snapshot(snapshot, player)

	# Need at least 1 CP to use, but save 1 for other stratagems if possible
	if player_cp < 1:
		return {
			"type": "DECLINE_TANK_SHOCK",
			"_ai_description": "AI declines Tank Shock (no CP)"
		}

	var vehicle_unit = snapshot.get("units", {}).get(vehicle_unit_id, {})
	if vehicle_unit.is_empty():
		return {
			"type": "DECLINE_TANK_SHOCK",
			"_ai_description": "AI declines Tank Shock (no vehicle data)"
		}

	var vehicle_name = vehicle_unit.get("meta", {}).get("name", vehicle_unit_id)
	var toughness = int(vehicle_unit.get("meta", {}).get("toughness", vehicle_unit.get("meta", {}).get("stats", {}).get("toughness", 4)))
	var dice_count = mini(toughness, 6)

	# Expected mortal wounds: dice_count * (2/6) = dice_count / 3
	var expected_mw = float(dice_count) / 3.0

	# Find the best target among enemies in engagement range
	# We use StratagemManager.get_tank_shock_eligible_targets if available,
	# otherwise estimate from snapshot
	var ts_main_loop = Engine.get_main_loop()
	var strat_manager_node = null
	if ts_main_loop and ts_main_loop is SceneTree and ts_main_loop.root:
		strat_manager_node = ts_main_loop.root.get_node_or_null("/root/StratagemManager")
	var eligible_targets = []
	if strat_manager_node:
		eligible_targets = strat_manager_node.get_tank_shock_eligible_targets(vehicle_unit_id, snapshot)

	if eligible_targets.is_empty():
		return {
			"type": "DECLINE_TANK_SHOCK",
			"_ai_description": "AI declines Tank Shock (no eligible targets)"
		}

	var best_target_id = ""
	var best_target_name = ""
	var best_target_score = 0.0

	for target_entry in eligible_targets:
		var target_unit_id = target_entry.get("unit_id", "")
		var target_unit = snapshot.get("units", {}).get(target_unit_id, {})
		if target_unit.is_empty():
			continue

		var target_name = target_entry.get("unit_name", target_unit_id)
		var wounds_per_model = _get_target_wounds_per_model(target_unit)
		var alive_models = _get_alive_models(target_unit)
		var alive_count = alive_models.size()

		# Score: higher when MW will kill models outright
		var score = expected_mw

		# Bonus if wounds_per_model is low (MW kills models outright)
		if wounds_per_model <= 2:
			score *= 1.5  # MW efficiently kills low-wound models
		elif wounds_per_model <= 3:
			score *= 1.2

		# Bonus for small remaining unit (finishing blow)
		if alive_count <= 3:
			score *= 1.3

		# Bonus for high-value targets
		var target_value = _estimate_unit_value(target_unit)
		if target_value >= 5.0:
			score *= 1.2

		if score > best_target_score:
			best_target_score = score
			best_target_id = target_unit_id
			best_target_name = target_name

	# Use if expected value is meaningful (>= 1.0 expected mortal wounds in effect)
	# and we have enough CP (or the score is high enough to justify spending last CP)
	if best_target_score >= 1.0 and best_target_id != "":
		# If this is our last CP, only use if really good value
		if player_cp <= 1 and best_target_score < 2.0:
			return {
				"type": "DECLINE_TANK_SHOCK",
				"_ai_description": "AI declines Tank Shock (saving last CP)"
			}

		print("AIDecisionMaker: Tank Shock — %s (T%d, %dD6) targeting %s (score: %.1f)" % [
			vehicle_name, toughness, dice_count, best_target_name, best_target_score])
		return {
			"type": "USE_TANK_SHOCK",
			"actor_unit_id": vehicle_unit_id,
			"payload": {
				"target_unit_id": best_target_id
			},
			"_ai_description": "AI uses Tank Shock with %s on %s (T%d, %.1f expected MW)" % [
				vehicle_name, best_target_name, toughness, expected_mw]
		}

	return {
		"type": "DECLINE_TANK_SHOCK",
		"_ai_description": "AI declines Tank Shock (low value)"
	}

# --- HEROIC INTERVENTION (Reactive — after opponent's charge) ---

static func evaluate_heroic_intervention(defending_player: int, charging_unit_id: String, snapshot: Dictionary) -> Dictionary:
	"""
	Evaluate whether the AI should use Heroic Intervention to counter-charge.
	Returns USE_HEROIC_INTERVENTION or DECLINE_HEROIC_INTERVENTION action dictionary.

	Heuristic: Heroic Intervention costs 2 CP and requires a charge roll.
	Use when:
	- We have a melee-capable unit nearby (within 6\" of the charging enemy)
	- The counter-charging unit is a strong melee fighter (CHARACTER with good melee)
	- CP is affordable (2 CP, save some for other uses)
	Skip when:
	- No strong melee units available
	- CP reserves are low (< 3 CP)
	- Counter-charger would be outmatched
	"""
	var player_cp = _get_player_cp_from_snapshot(snapshot, defending_player)

	# Heroic Intervention costs 2 CP — need at least 2, prefer 3+
	if player_cp < 2:
		return {
			"type": "DECLINE_HEROIC_INTERVENTION",
			"player": defending_player,
			"_ai_description": "AI declines Heroic Intervention (insufficient CP)"
		}

	# Get eligible units from StratagemManager
	var main_loop = Engine.get_main_loop()
	var strat_manager_node = null
	if main_loop and main_loop is SceneTree and main_loop.root:
		strat_manager_node = main_loop.root.get_node_or_null("/root/StratagemManager")
	if not strat_manager_node:
		return {
			"type": "DECLINE_HEROIC_INTERVENTION",
			"player": defending_player,
			"_ai_description": "AI declines Heroic Intervention"
		}

	var eligible_units = strat_manager_node.get_heroic_intervention_eligible_units(
		defending_player, charging_unit_id, snapshot
	)

	if eligible_units.is_empty():
		return {
			"type": "DECLINE_HEROIC_INTERVENTION",
			"player": defending_player,
			"_ai_description": "AI declines Heroic Intervention (no eligible units)"
		}

	var charging_unit = snapshot.get("units", {}).get(charging_unit_id, {})
	var charging_value = _estimate_unit_value(charging_unit)

	var best_unit_id = ""
	var best_unit_name = ""
	var best_score = 0.0

	for entry in eligible_units:
		var unit_id = entry.get("unit_id", "")
		var unit_name = entry.get("unit_name", unit_id)
		var unit = snapshot.get("units", {}).get(unit_id, {})
		if unit.is_empty():
			continue

		# Score the counter-charge candidate
		var score = 0.0
		var keywords = unit.get("meta", {}).get("keywords", [])
		var has_melee = _unit_has_melee_weapons(unit)

		# Must have melee weapons to be useful
		if not has_melee:
			continue

		# Base score from unit value (stronger units are better counter-chargers)
		var unit_value = _estimate_unit_value(unit)
		score += unit_value * 0.5

		# Bonus for CHARACTER units (they usually have strong melee)
		for kw in keywords:
			var kw_upper = kw.to_upper()
			if kw_upper == "CHARACTER":
				score += 2.0
			elif kw_upper == "MONSTER":
				score += 1.0

		# Scale by enemy value (worth counter-charging valuable enemies)
		if charging_value >= 5.0:
			score *= 1.3
		elif charging_value <= 2.0:
			score *= 0.5  # Not worth 2 CP against cheap units

		if score > best_score:
			best_score = score
			best_unit_id = unit_id
			best_unit_name = unit_name

	# Use if score is high enough to justify 2 CP
	# Threshold higher than other stratagems because of cost and charge roll uncertainty
	if best_score >= 3.0 and best_unit_id != "":
		# If CP is tight (exactly 2), only use against very valuable targets
		if player_cp <= 2 and best_score < 5.0:
			return {
				"type": "DECLINE_HEROIC_INTERVENTION",
				"player": defending_player,
				"_ai_description": "AI declines Heroic Intervention (saving CP)"
			}

		print("AIDecisionMaker: Heroic Intervention — %s counter-charges (score: %.1f)" % [best_unit_name, best_score])
		return {
			"type": "USE_HEROIC_INTERVENTION",
			"player": defending_player,
			"payload": {
				"unit_id": best_unit_id
			},
			"_ai_description": "AI uses Heroic Intervention with %s (score: %.1f)" % [best_unit_name, best_score]
		}

	return {
		"type": "DECLINE_HEROIC_INTERVENTION",
		"player": defending_player,
		"_ai_description": "AI declines Heroic Intervention (low value)"
	}

static func _count_unit_ranged_shots(unit: Dictionary) -> float:
	"""Count total expected ranged attacks for a unit (all alive models * all ranged weapons)."""
	var total = 0.0
	var weapons = unit.get("meta", {}).get("weapons", [])
	var alive = _get_alive_models(unit)
	var model_count = alive.size()

	for w in weapons:
		if w.get("type", "").to_lower() != "ranged":
			continue
		var attacks_str = w.get("attacks", "1")
		var attacks = 0.0
		if attacks_str.is_valid_float():
			attacks = float(attacks_str)
		elif attacks_str.is_valid_int():
			attacks = float(attacks_str)
		elif "d" in attacks_str.to_lower():
			# Variable attacks: use average
			attacks = _parse_average_damage(attacks_str)
		else:
			attacks = 1.0
		total += attacks * model_count

	return total

static func _estimate_unit_value(unit: Dictionary) -> float:
	"""
	Estimate the tactical value of a unit for stratagem decisions.
	Returns a rough score: higher = more valuable.
	"""
	var keywords = unit.get("meta", {}).get("keywords", [])
	var stats = unit.get("meta", {}).get("stats", {})
	var wounds_per_model = int(stats.get("wounds", 1))
	var alive = _get_alive_models(unit)
	var alive_count = alive.size()
	var value = float(alive_count) * float(wounds_per_model) * 0.5

	for kw in keywords:
		var kw_upper = kw.to_upper()
		if kw_upper == "CHARACTER":
			value += 3.0
		elif kw_upper == "VEHICLE":
			value += 2.0
		elif kw_upper == "MONSTER":
			value += 2.0

	return value

# --- COMMAND RE-ROLL (Reactive — after any dice roll) ---

static func evaluate_command_reroll_charge(player: int, rolled_distance: int, required_distance: int, snapshot: Dictionary) -> bool:
	"""
	Evaluate whether the AI should re-roll a charge roll.
	Returns true if the re-roll is worthwhile.

	Heuristic: Re-roll if the charge FAILED and:
	- The gap between rolled and required is small (reroll has reasonable chance)
	- The charging unit is important (character, elite unit)
	"""
	if rolled_distance >= required_distance:
		return false  # Charge already succeeded — no need to reroll

	var gap = required_distance - rolled_distance
	# Probability of rolling required on 2D6:
	# 2D6 average = 7, so if we need 7+ the chance is ~58.3%
	# Need 8+ = ~41.7%, 9+ = ~27.8%, 10+ = ~16.7%, 11+ = ~8.3%, 12 = ~2.8%
	# Don't reroll if we need 11+ (too unlikely)
	if required_distance > 10:
		return false

	# If the roll was close to required (within 2), always reroll
	if gap <= 2 and required_distance <= 9:
		return true

	# If the roll was terrible (e.g. rolled 3 on 2D6, needed 7), reroll
	if rolled_distance <= 4 and required_distance <= 9:
		return true

	# For moderate gaps, check CP affordability
	var player_cp = _get_player_cp_from_snapshot(snapshot, player)
	if player_cp >= 3 and required_distance <= 9:
		return true  # We can afford it, take the shot

	return false

static func evaluate_command_reroll_battleshock(player: int, roll: int, leadership: int, snapshot: Dictionary) -> bool:
	"""
	Evaluate whether the AI should re-roll a failed battle-shock test.
	Returns true if the re-roll is worthwhile.

	Heuristic: Re-roll if:
	- The unit needs the test to pass (e.g. holding an objective)
	- The gap between roll and leadership is small
	"""
	if roll <= leadership:
		return false  # Already passed

	var gap = roll - leadership
	# Re-rolling 2D6: if we need to roll <= leadership, higher leadership = more likely
	# Leadership 6: need 6 or less = 41.7% on 2D6
	# Leadership 7: need 7 or less = 58.3%
	# Leadership 8: need 8 or less = 72.2%

	# Always reroll if leadership is 7+ (good chance of passing)
	if leadership >= 7:
		return true

	# Reroll if the gap is small (within 2)
	if gap <= 2:
		return true

	# If leadership is very low (5 or less), don't waste CP
	if leadership <= 5:
		return false

	return true

static func evaluate_command_reroll_advance(player: int, advance_roll: int, snapshot: Dictionary) -> bool:
	"""
	Evaluate whether the AI should re-roll an advance roll.
	Returns true if the re-roll is worthwhile.

	Heuristic: Re-roll if the roll is very low (1 or 2) since advancing
	is usually done when the extra distance matters.
	"""
	# Only reroll very low advance rolls — a 1 is the worst possible
	if advance_roll <= 1:
		return true
	if advance_roll <= 2:
		# Check if CP is plentiful
		var player_cp = _get_player_cp_from_snapshot(snapshot, player)
		if player_cp >= 3:
			return true

	return false

# --- HELPER: Get player CP from snapshot ---

static func _get_player_cp_from_snapshot(snapshot: Dictionary, player: int) -> int:
	"""Get a player's CP from the game state snapshot."""
	var players = snapshot.get("players", {})
	var player_data = players.get(str(player), players.get(player, {}))
	return int(player_data.get("cp", 0))

# =============================================================================
# ENEMY THREAT RANGE AWARENESS (AI-TACTIC-4, MOV-2)
# =============================================================================
# Calculates charge threat zones and shooting ranges for enemy units,
# allowing the AI to avoid moving into danger when not tactically necessary.

static func _calculate_enemy_threat_data(enemies: Dictionary) -> Array:
	"""Build an array of threat data for each enemy unit.
	Each entry: {unit_id, centroid, charge_threat_px, shoot_threat_px, has_melee, has_ranged, unit_value}
	charge_threat_px = (enemy M + 12" charge + 1" ER) in pixels
	shoot_threat_px = max ranged weapon range in pixels"""
	var threat_data = []
	for enemy_id in enemies:
		var enemy = enemies[enemy_id]
		var ecentroid = _get_unit_centroid(enemy)
		if ecentroid == Vector2.INF:
			continue
		var enemy_stats = enemy.get("meta", {}).get("stats", {})
		var enemy_move = float(enemy_stats.get("move", 6))
		var has_melee = _unit_has_melee_weapons(enemy)
		var has_ranged = _unit_has_ranged_weapons(enemy)
		var max_shoot_range = _get_max_weapon_range(enemy)  # in inches

		# Charge threat range = Movement + 12" max charge + 1" engagement range
		# This represents the maximum distance this unit could reach with a move + charge
		var charge_threat_inches = enemy_move + 12.0 + 1.0
		var charge_threat_px = charge_threat_inches * PIXELS_PER_INCH

		# Shooting threat range = max weapon range
		var shoot_threat_px = max_shoot_range * PIXELS_PER_INCH

		# Estimate unit value/lethality for weighting the threat
		var unit_value = _estimate_enemy_threat_level(enemy)

		threat_data.append({
			"unit_id": enemy_id,
			"centroid": ecentroid,
			"charge_threat_px": charge_threat_px,
			"shoot_threat_px": shoot_threat_px,
			"has_melee": has_melee,
			"has_ranged": has_ranged,
			"unit_value": unit_value
		})
	return threat_data

static func _estimate_enemy_threat_level(enemy: Dictionary) -> float:
	"""Estimate how dangerous an enemy unit is (0.0 to 3.0 scale).
	Used to weight threat zones — more dangerous enemies create scarier zones."""
	var value = 1.0
	var keywords = enemy.get("meta", {}).get("keywords", [])
	var stats = enemy.get("meta", {}).get("stats", {})

	# More alive models = more dangerous
	var alive_count = 0
	for model in enemy.get("models", []):
		if model.get("alive", true):
			alive_count += 1
	if alive_count >= 10:
		value += 0.5
	elif alive_count <= 2:
		value -= 0.2

	# High toughness / wounds suggests elite unit
	var toughness = int(stats.get("toughness", 4))
	var wounds = int(stats.get("wounds", 1))
	if toughness >= 8 or wounds >= 8:
		value += 0.5  # Heavy hitters (vehicles, monsters)
	if wounds >= 4:
		value += 0.3

	# Characters and leader-attached units are more threatening
	if "CHARACTER" in keywords or "VEHICLE" in keywords or "MONSTER" in keywords:
		value += 0.3

	return clampf(value, 0.3, 3.0)

static func _evaluate_position_threat(
	pos: Vector2, threat_data: Array, own_unit: Dictionary
) -> Dictionary:
	"""Evaluate the threat level at a specific position from all enemy units.
	Returns {charge_threat: float, shoot_threat: float, total_threat: float, threats: Array}
	Higher values = more dangerous position."""
	var charge_threat = 0.0
	var shoot_threat = 0.0
	var threats = []  # Details of which enemies threaten this position
	var is_melee_focused = _unit_has_melee_weapons(own_unit) and not _unit_has_ranged_weapons(own_unit)

	for td in threat_data:
		var dist = pos.distance_to(td.centroid)

		# Check charge threat zone (enemy could move + charge to reach here)
		if td.has_melee and dist < td.charge_threat_px:
			# How deep into the charge threat zone are we? (0.0 = edge, 1.0 = right on top)
			var depth = 1.0 - (dist / td.charge_threat_px)
			var charge_penalty = depth * td.unit_value * THREAT_CHARGE_PENALTY
			# Melee units care less about being charged (they want to fight)
			if is_melee_focused:
				charge_penalty *= THREAT_MELEE_UNIT_IGNORE
			charge_threat += charge_penalty
			threats.append({
				"enemy_id": td.unit_id,
				"type": "charge",
				"distance_inches": dist / PIXELS_PER_INCH,
				"threat_range_inches": td.charge_threat_px / PIXELS_PER_INCH,
				"penalty": charge_penalty
			})

		# Check shooting threat zone
		if td.has_ranged and td.shoot_threat_px > 0 and dist < td.shoot_threat_px:
			var depth = 1.0 - (dist / td.shoot_threat_px)
			var shoot_penalty = depth * td.unit_value * THREAT_SHOOTING_PENALTY
			shoot_threat += shoot_penalty
			threats.append({
				"enemy_id": td.unit_id,
				"type": "shooting",
				"distance_inches": dist / PIXELS_PER_INCH,
				"threat_range_inches": td.shoot_threat_px / PIXELS_PER_INCH,
				"penalty": shoot_penalty
			})

	var total_threat = charge_threat + shoot_threat

	# Fragile units (low toughness, few wounds) get extra penalty in danger
	var own_stats = own_unit.get("meta", {}).get("stats", {})
	var own_toughness = int(own_stats.get("toughness", 4))
	var own_wounds = int(own_stats.get("wounds", 1))
	if own_toughness <= 3 or own_wounds <= 1:
		total_threat *= THREAT_FRAGILE_BONUS

	return {
		"charge_threat": charge_threat,
		"shoot_threat": shoot_threat,
		"total_threat": total_threat,
		"threats": threats
	}

static func _is_position_in_charge_threat(pos: Vector2, threat_data: Array) -> bool:
	"""Quick check: is this position within any enemy's charge threat range?"""
	for td in threat_data:
		if not td.has_melee:
			continue
		var dist = pos.distance_to(td.centroid)
		if dist < td.charge_threat_px:
			return true
	return false

static func _find_safer_position(
	current_pos: Vector2, desired_pos: Vector2, move_px: float,
	threat_data: Array, own_unit: Dictionary, objectives: Array
) -> Vector2:
	"""Given a desired movement destination, try to find a nearby position that
	reduces threat exposure while still making progress toward the objective.
	Returns the adjusted position, or desired_pos if no safer alternative exists."""
	var desired_threat = _evaluate_position_threat(desired_pos, threat_data, own_unit)
	var current_threat = _evaluate_position_threat(current_pos, threat_data, own_unit)

	# If the desired position is not significantly more dangerous, keep it
	if desired_threat.total_threat <= 0.5 or desired_threat.total_threat <= current_threat.total_threat:
		return desired_pos

	# Only try to find safer positions if the threat increase is meaningful
	if desired_threat.total_threat - current_threat.total_threat < 1.0:
		return desired_pos

	# Try positions along the same general direction but offset to reduce threat
	var move_dir = (desired_pos - current_pos)
	var move_dist = move_dir.length()
	if move_dist < 1.0:
		return desired_pos
	move_dir = move_dir.normalized()

	var best_pos = desired_pos
	var best_score = -INF

	# Score = progress toward target - threat penalty
	# We want to still move forward but choose a less threatened position
	var perp = Vector2(-move_dir.y, move_dir.x)

	# Try: original, slightly left/right, shorter move, shorter + offset
	var candidates = [desired_pos]

	# Lateral offsets (dodge sideways)
	for offset_mult in [1.0, -1.0, 2.0, -2.0]:
		var offset = perp * (PIXELS_PER_INCH * 2.0) * offset_mult
		var candidate = desired_pos + offset
		candidate.x = clamp(candidate.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		candidate.y = clamp(candidate.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
		if current_pos.distance_to(candidate) <= move_px:
			candidates.append(candidate)

	# Shorter moves (stop just outside charge threat)
	for fraction in [0.75, 0.5]:
		var shorter = current_pos + move_dir * move_dist * fraction
		shorter.x = clamp(shorter.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
		shorter.y = clamp(shorter.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
		candidates.append(shorter)
		# Also try shorter + lateral offset
		for offset_mult in [1.0, -1.0]:
			var offset = perp * (PIXELS_PER_INCH * 2.0) * offset_mult
			var combo = shorter + offset
			combo.x = clamp(combo.x, BASE_MARGIN_PX, BOARD_WIDTH_PX - BASE_MARGIN_PX)
			combo.y = clamp(combo.y, BASE_MARGIN_PX, BOARD_HEIGHT_PX - BASE_MARGIN_PX)
			if current_pos.distance_to(combo) <= move_px:
				candidates.append(combo)

	# Find nearest objective for progress scoring
	var target_obj = _nearest_objective_pos(desired_pos, objectives)

	for candidate in candidates:
		var cand_threat = _evaluate_position_threat(candidate, threat_data, own_unit)
		# Progress = how much closer to the target objective compared to current position
		var progress = 0.0
		if target_obj != Vector2.INF:
			var current_dist_to_obj = current_pos.distance_to(target_obj)
			var cand_dist_to_obj = candidate.distance_to(target_obj)
			progress = (current_dist_to_obj - cand_dist_to_obj) / PIXELS_PER_INCH  # Inches gained toward objective
		# Score: progress matters, but reducing threat also matters
		var score = progress * 1.5 - cand_threat.total_threat
		if score > best_score:
			best_score = score
			best_pos = candidate

	if best_pos != desired_pos:
		print("AIDecisionMaker: Threat-adjusted position from (%.0f, %.0f) to (%.0f, %.0f) — threat %.1f -> %.1f" % [
			desired_pos.x, desired_pos.y, best_pos.x, best_pos.y,
			desired_threat.total_threat,
			_evaluate_position_threat(best_pos, threat_data, own_unit).total_threat
		])

	return best_pos
