extends Node

# RulesEngine - Central authority for game rules validation and resolution
# Handles shooting mechanics, dice rolling, damage application following 10e rules
# This is an autoload singleton, accessed globally as RulesEngine

# Weapon profile structure (will be expanded later)
const WEAPON_PROFILES = {
	"bolt_rifle": {
		"name": "Bolt Rifle",
		"range": 30,
		"attacks": 2,
		"bs": 3,
		"strength": 4,
		"ap": 1,
		"damage": 1,
		"keywords": []
	},
	"plasma_pistol": {
		"name": "Plasma Pistol", 
		"range": 120,  # Extended range for debugging
		"attacks": 1,
		"bs": 3,
		"strength": 7,
		"ap": 3,
		"damage": 1,
		"keywords": ["PISTOL"]
	},
	"slugga": {
		"name": "Slugga",
		"range": 12,
		"attacks": 1,
		"bs": 5,
		"strength": 4,
		"ap": 0,
		"damage": 1,
		"keywords": ["PISTOL"]
	},
	"grot_blasta": {
		"name": "Grot Blasta",
		"range": 12,
		"attacks": 1,
		"bs": 4,
		"strength": 3,
		"ap": 0,
		"damage": 1,
		"keywords": []
	}
}

# Unit weapon loadouts (MVP - simplified)
const UNIT_WEAPONS = {
	"U_INTERCESSORS_A": {
		"m1": ["bolt_rifle"],
		"m2": ["bolt_rifle"],
		"m3": ["bolt_rifle"],
		"m4": ["bolt_rifle"],
		"m5": ["bolt_rifle", "plasma_pistol"]  # Sergeant
	},
	"U_TACTICAL_A": {
		"m1": ["bolt_rifle"],
		"m2": ["bolt_rifle"],
		"m3": ["bolt_rifle"],
		"m4": ["bolt_rifle"],
		"m5": ["bolt_rifle", "plasma_pistol"]  # Sergeant
	},
	"U_BOYZ_A": {
		"m1": ["slugga"],
		"m2": ["slugga"],
		"m3": ["slugga"],
		"m4": ["slugga"],
		"m5": ["slugga"],
		"m6": ["slugga"],
		"m7": ["slugga"],
		"m8": ["slugga"],
		"m9": ["slugga"],
		"m10": ["slugga"]
	},
	"U_GRETCHIN_A": {
		"m1": ["grot_blasta"],
		"m2": ["grot_blasta"],
		"m3": ["grot_blasta"],
		"m4": ["grot_blasta"],
		"m5": ["grot_blasta"]
	}
}

# RNG Service for deterministic dice rolling
class RNGService:
	var rng: RandomNumberGenerator
	
	func _init(seed_value: int = -1):
		rng = RandomNumberGenerator.new()
		if seed_value >= 0:
			rng.seed = seed_value
		else:
			rng.randomize()
	
	func roll_d6(count: int) -> Array:
		var rolls = []
		for i in count:
			rolls.append(rng.randi_range(1, 6))
		return rolls

# Main shooting resolution entry point
static func resolve_shoot(action: Dictionary, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
	if not rng_service:
		rng_service = RNGService.new()
	
	var result = {
		"success": true,
		"phase": "SHOOTING",
		"diffs": [],
		"dice": [],
		"log_text": ""
	}
	
	var actor_unit_id = action.get("actor_unit_id", "")
	var assignments = action.get("payload", {}).get("assignments", [])
	
	if assignments.is_empty():
		result.success = false
		result.log_text = "No weapon assignments provided"
		return result
	
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	
	if actor_unit.is_empty():
		result.success = false
		result.log_text = "Actor unit not found"
		return result
	
	# Process each weapon assignment
	for assignment in assignments:
		var assignment_result = _resolve_assignment(assignment, actor_unit_id, board, rng_service)
		result.diffs.append_array(assignment_result.diffs)
		result.dice.append_array(assignment_result.dice)
		if assignment_result.log_text:
			result.log_text += assignment_result.log_text + "\n"
	
	return result

# Resolve a single weapon assignment (models with weapon -> target)
static func _resolve_assignment(assignment: Dictionary, actor_unit_id: String, board: Dictionary, rng: RNGService) -> Dictionary:
	var result = {
		"diffs": [],
		"dice": [],
		"log_text": ""
	}
	
	var model_ids = assignment.get("model_ids", [])
	var weapon_id = assignment.get("weapon_id", "")
	var target_unit_id = assignment.get("target_unit_id", "")
	
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})
	
	if target_unit.is_empty():
		result.log_text = "Target unit not found"
		return result
	
	# Get weapon profile
	var weapon_profile = WEAPON_PROFILES.get(weapon_id, {})
	if weapon_profile.is_empty():
		result.log_text = "Unknown weapon: " + weapon_id
		return result
	
	# Calculate total attacks
	var total_attacks = model_ids.size() * weapon_profile.get("attacks", 1)
	if assignment.has("attacks_override") and assignment.attacks_override != null:
		total_attacks = assignment.attacks_override
	
	# Roll to hit
	var hit_rolls = rng.roll_d6(total_attacks)
	var bs = weapon_profile.get("bs", 4)
	var hits = 0
	for roll in hit_rolls:
		if roll >= bs:
			hits += 1
	
	result.dice.append({
		"context": "to_hit",
		"threshold": str(bs) + "+",
		"rolls_raw": hit_rolls,
		"successes": hits
	})
	
	if hits == 0:
		result.log_text = "%s → %s: No hits" % [actor_unit.get("meta", {}).get("name", actor_unit_id), target_unit.get("meta", {}).get("name", target_unit_id)]
		return result
	
	# Roll to wound
	var strength = weapon_profile.get("strength", 4)
	var toughness = target_unit.get("meta", {}).get("stats", {}).get("toughness", 4)
	var wound_threshold = _calculate_wound_threshold(strength, toughness)
	
	var wound_rolls = rng.roll_d6(hits)
	var wounds_caused = 0
	for roll in wound_rolls:
		if roll >= wound_threshold:
			wounds_caused += 1
	
	result.dice.append({
		"context": "to_wound",
		"threshold": str(wound_threshold) + "+",
		"rolls_raw": wound_rolls,
		"successes": wounds_caused
	})
	
	if wounds_caused == 0:
		result.log_text = "%s → %s: %d hits, no wounds" % [actor_unit.get("meta", {}).get("name", actor_unit_id), target_unit.get("meta", {}).get("name", target_unit_id), hits]
		return result
	
	# Process saves and damage
	var ap = weapon_profile.get("ap", 0)
	var damage = weapon_profile.get("damage", 1)
	var casualties = 0
	var damage_applied = 0
	
	# Get target unit's save value
	var base_save = target_unit.get("meta", {}).get("stats", {}).get("save", 7)
	
	# Find allocation focus model (if any model was previously wounded)
	var allocation_focus_model_id = null
	var models = target_unit.get("models", [])
	for i in range(models.size()):
		var model = models[i]
		if model.get("alive", true):
			var wounds = model.get("wounds", 1)
			var current_wounds = model.get("current_wounds", wounds)
			if current_wounds < wounds:
				allocation_focus_model_id = model.get("id", "m%d" % i)
				break
	
	# Allocate wounds
	for wound_idx in range(wounds_caused):
		# Select target model
		var target_model = null
		var target_model_index = -1
		
		if allocation_focus_model_id:
			# Must allocate to previously wounded model
			for i in range(models.size()):
				var model = models[i]
				if model.get("id", "m%d" % i) == allocation_focus_model_id and model.get("alive", true):
					target_model = model
					target_model_index = i
					break
		
		if not target_model:
			# Find first alive model
			for i in range(models.size()):
				var model = models[i]
				if model.get("alive", true):
					target_model = model
					target_model_index = i
					allocation_focus_model_id = model.get("id", "m%d" % i)
					break
		
		if not target_model:
			break  # No more models to allocate to
		
		# Check for cover
		var has_cover = _check_model_has_cover(target_model, actor_unit_id, board)
		
		# Calculate save needed
		var save_result = _calculate_save_needed(base_save, ap, has_cover, target_model.get("invuln", 0))
		
		# Roll save
		var save_roll = rng.roll_d6(1)[0]
		var saved = false
		
		if save_result.use_invuln:
			saved = save_roll >= save_result.inv
		else:
			saved = save_roll >= save_result.armour
		
		result.dice.append({
			"context": "save",
			"sv": str(base_save) + "+",
			"ap": ap,
			"cover": "+1 (capped)" if has_cover and not save_result.use_invuln else "none",
			"rolls_raw": [save_roll],
			"fails": 0 if saved else 1
		})
		
		if not saved:
			# Apply damage
			var current_wounds = target_model.get("current_wounds", target_model.get("wounds", 1))
			var new_wounds = max(0, current_wounds - damage)
			
			result.diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.current_wounds" % [target_unit_id, target_model_index],
				"value": new_wounds
			})
			
			damage_applied += damage
			
			if new_wounds == 0:
				# Model destroyed
				result.diffs.append({
					"op": "set",
					"path": "units.%s.models.%d.alive" % [target_unit_id, target_model_index],
					"value": false
				})
				casualties += 1
				allocation_focus_model_id = null  # Need new allocation target
	
	# Build log text
	var actor_name = actor_unit.get("meta", {}).get("name", actor_unit_id)
	var target_name = target_unit.get("meta", {}).get("name", target_unit_id)
	
	if casualties > 0:
		result.log_text = "%s → %s: %d hits, %d wounds, %d failed saves → %d slain" % [actor_name, target_name, hits, wounds_caused, wounds_caused - (wounds_caused - casualties), casualties]
	else:
		result.log_text = "%s → %s: %d hits, %d wounds, all saved" % [actor_name, target_name, hits, wounds_caused]
	
	return result

# Validation functions
static func validate_shoot(action: Dictionary, board: Dictionary) -> Dictionary:
	var errors = []
	
	var actor_unit_id = action.get("actor_unit_id", "")
	if actor_unit_id == "":
		errors.append("Missing actor_unit_id")
		return {"valid": false, "errors": errors}
	
	var assignments = action.get("payload", {}).get("assignments", [])
	if assignments.is_empty():
		errors.append("No weapon assignments provided")
		return {"valid": false, "errors": errors}
	
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	
	if actor_unit.is_empty():
		errors.append("Actor unit not found")
		return {"valid": false, "errors": errors}
	
	# Check if unit can shoot
	var flags = actor_unit.get("flags", {})
	if flags.get("cannot_shoot", false):
		errors.append("Unit cannot shoot (advanced or fell back)")
	
	# Validate each assignment
	for assignment in assignments:
		var weapon_id = assignment.get("weapon_id", "")
		var target_unit_id = assignment.get("target_unit_id", "")
		
		if weapon_id == "":
			errors.append("Assignment missing weapon_id")
		elif not WEAPON_PROFILES.has(weapon_id):
			errors.append("Unknown weapon: " + weapon_id)
		
		if target_unit_id == "":
			errors.append("Assignment missing target_unit_id")
		elif not units.has(target_unit_id):
			errors.append("Target unit not found: " + target_unit_id)
		else:
			var target_unit = units[target_unit_id]
			if target_unit.get("owner", 0) == actor_unit.get("owner", 0):
				errors.append("Cannot target friendly units")
			
			# Check range and visibility
			if weapon_id != "" and WEAPON_PROFILES.has(weapon_id):
				var visibility_result = _check_target_visibility(actor_unit_id, target_unit_id, weapon_id, board)
				if not visibility_result.visible:
					errors.append(visibility_result.reason)
	
	return {"valid": errors.is_empty(), "errors": errors}

# Helper functions
static func _calculate_wound_threshold(strength: int, toughness: int) -> int:
	# 10e wound chart
	if strength >= toughness * 2:
		return 2  # 2+
	elif strength > toughness:
		return 3  # 3+
	elif strength == toughness:
		return 4  # 4+
	elif strength * 2 <= toughness:
		return 6  # 6+
	else:
		return 5  # 5+

static func _calculate_save_needed(base_save: int, ap: int, has_cover: bool, invuln: int) -> Dictionary:
	# Calculate armour save with AP and cover
	var armour_save = base_save + ap  # AP makes saves worse (higher number needed)
	
	# Apply cover if applicable
	if has_cover and ap == 0 and base_save <= 3:
		# 3+ or better save doesn't benefit from cover vs AP 0
		has_cover = false
	
	if has_cover:
		armour_save -= 1  # Cover improves save by 1
	
	# Cap save improvement at +1 total
	var improvement = base_save - armour_save
	if improvement > 1:
		armour_save = base_save - 1
	
	# Saves can never be better than 2+
	armour_save = max(2, armour_save)
	
	# Check if invuln is better (invuln ignores AP)
	var use_invuln = false
	if invuln > 0 and invuln < armour_save:
		use_invuln = true
	
	return {
		"armour": armour_save,
		"inv": invuln if invuln > 0 else 99,
		"use_invuln": use_invuln,
		"cap_applied": improvement > 1
	}

static func _check_target_visibility(actor_unit_id: String, target_unit_id: String, weapon_id: String, board: Dictionary) -> Dictionary:
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	var target_unit = units.get(target_unit_id, {})
	var weapon_profile = WEAPON_PROFILES.get(weapon_id, {})
	
	if actor_unit.is_empty() or target_unit.is_empty() or weapon_profile.is_empty():
		return {"visible": false, "reason": "Invalid units or weapon"}
	
	var weapon_range = weapon_profile.get("range", 12)
	var range_px = Measurement.inches_to_px(weapon_range)
	
	# Check if any model in actor unit can see and is in range of any model in target unit
	var actor_models = actor_unit.get("models", [])
	var target_models = target_unit.get("models", [])
	
	for actor_model in actor_models:
		if not actor_model.get("alive", true):
			continue
		
		var actor_pos = _get_model_position(actor_model)
		if not actor_pos:
			continue
		
		for target_model in target_models:
			if not target_model.get("alive", true):
				continue
			
			var target_pos = _get_model_position(target_model)
			if not target_pos:
				continue
			
			# Check range
			var distance = actor_pos.distance_to(target_pos)
			if distance <= range_px:
				# Check LoS
				if _check_line_of_sight(actor_pos, target_pos, board):
					return {"visible": true, "reason": ""}
	
	return {"visible": false, "reason": "No valid targets in range and LoS"}

static func _check_line_of_sight(from_pos: Vector2, to_pos: Vector2, board: Dictionary) -> bool:
	# MVP: Simple LoS check against obscuring terrain
	var terrain = board.get("board", {}).get("terrain", [])
	
	for terrain_piece in terrain:
		if terrain_piece.get("type", "") == "obscuring":
			var poly = terrain_piece.get("poly", [])
			if _segment_intersects_polygon(from_pos, to_pos, poly):
				return false
	
	return true

static func _segment_intersects_polygon(seg_start: Vector2, seg_end: Vector2, poly: Array) -> bool:
	# MVP: Treat polygon as rectangle bounds
	if poly.is_empty():
		return false
	
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	
	for vertex in poly:
		var x = vertex.get("x", 0) if vertex is Dictionary else vertex.x
		var y = vertex.get("y", 0) if vertex is Dictionary else vertex.y
		min_x = min(min_x, x)
		max_x = max(max_x, x)
		min_y = min(min_y, y)
		max_y = max(max_y, y)
	
	# Check if segment intersects rectangle
	return _segment_rect_intersection(seg_start, seg_end, Vector2(min_x, min_y), Vector2(max_x, max_y))

static func _segment_rect_intersection(seg_start: Vector2, seg_end: Vector2, rect_min: Vector2, rect_max: Vector2) -> bool:
	# Check if segment intersects axis-aligned rectangle
	var t_min = 0.0
	var t_max = 1.0
	var delta = seg_end - seg_start
	
	for axis in [0, 1]:  # x and y axes
		if abs(delta[axis]) < 0.0001:
			# Segment parallel to axis
			if seg_start[axis] < rect_min[axis] or seg_start[axis] > rect_max[axis]:
				return false
		else:
			var t1 = (rect_min[axis] - seg_start[axis]) / delta[axis]
			var t2 = (rect_max[axis] - seg_start[axis]) / delta[axis]
			
			if t1 > t2:
				var temp = t1
				t1 = t2
				t2 = temp
			
			t_min = max(t_min, t1)
			t_max = min(t_max, t2)
			
			if t_min > t_max:
				return false
	
	return true

static func _check_model_has_cover(model: Dictionary, shooting_unit_id: String, board: Dictionary) -> bool:
	# MVP: Check if model is in or behind light cover
	var model_pos = _get_model_position(model)
	if not model_pos:
		return false
	
	var terrain = board.get("board", {}).get("terrain", [])
	var units = board.get("units", {})
	var shooting_unit = units.get(shooting_unit_id, {})
	
	# Check if model is inside light cover terrain
	for terrain_piece in terrain:
		if terrain_piece.get("type", "") == "light_cover":
			var poly = terrain_piece.get("poly", [])
			if _point_in_polygon(model_pos, poly):
				return true
	
	# Check if LoS crosses light cover (model behind it)
	var shooting_models = shooting_unit.get("models", [])
	for shooter in shooting_models:
		if not shooter.get("alive", true):
			continue
		
		var shooter_pos = _get_model_position(shooter)
		if not shooter_pos:
			continue
		
		for terrain_piece in terrain:
			if terrain_piece.get("type", "") == "light_cover":
				var poly = terrain_piece.get("poly", [])
				if _segment_intersects_polygon(shooter_pos, model_pos, poly):
					# Check if target is behind cover (further from shooter than cover)
					var cover_center = _polygon_center(poly)
					var dist_to_cover = shooter_pos.distance_to(cover_center)
					var dist_to_target = shooter_pos.distance_to(model_pos)
					if dist_to_target > dist_to_cover:
						return true
	
	return false

static func _point_in_polygon(point: Vector2, poly: Array) -> bool:
	# MVP: Rectangle bounds check
	if poly.is_empty():
		return false
	
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	
	for vertex in poly:
		var x = vertex.get("x", 0) if vertex is Dictionary else vertex.x
		var y = vertex.get("y", 0) if vertex is Dictionary else vertex.y
		min_x = min(min_x, x)
		max_x = max(max_x, x)
		min_y = min(min_y, y)
		max_y = max(max_y, y)
	
	return point.x >= min_x and point.x <= max_x and point.y >= min_y and point.y <= max_y

static func _polygon_center(poly: Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	
	var sum = Vector2.ZERO
	for vertex in poly:
		var x = vertex.get("x", 0) if vertex is Dictionary else vertex.x
		var y = vertex.get("y", 0) if vertex is Dictionary else vertex.y
		sum += Vector2(x, y)
	
	return sum / poly.size()

static func _get_model_position(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

# Utility functions for getting eligible targets
static func get_eligible_targets(actor_unit_id: String, board: Dictionary) -> Dictionary:
	var eligible = {}
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	
	if actor_unit.is_empty():
		return eligible
	
	var actor_owner = actor_unit.get("owner", 0)
	
	# Check each potential target unit
	for target_unit_id in units:
		var target_unit = units[target_unit_id]
		
		# Skip friendly units
		if target_unit.get("owner", 0) == actor_owner:
			continue
		
		# Skip destroyed units
		var has_alive_models = false
		for model in target_unit.get("models", []):
			if model.get("alive", true):
				has_alive_models = true
				break
		
		if not has_alive_models:
			continue
		
		# Check weapons that can target this unit
		var weapons_in_range = []
		var unit_weapons = UNIT_WEAPONS.get(actor_unit_id, {})
		
		for model_id in unit_weapons:
			var model = _get_model_by_id(actor_unit, model_id)
			if not model or not model.get("alive", true):
				continue
			
			for weapon_id in unit_weapons[model_id]:
				if weapon_id in weapons_in_range:
					continue
				
				var visibility = _check_target_visibility(actor_unit_id, target_unit_id, weapon_id, board)
				if visibility.visible:
					weapons_in_range.append(weapon_id)
		
		if not weapons_in_range.is_empty():
			eligible[target_unit_id] = {
				"weapons_in_range": weapons_in_range,
				"unit_name": target_unit.get("meta", {}).get("name", target_unit_id)
			}
	
	return eligible

static func _get_model_by_id(unit: Dictionary, model_id: String) -> Dictionary:
	for model in unit.get("models", []):
		if model.get("id", "") == model_id:
			return model
	return {}

# Get weapons for a unit
static func get_unit_weapons(unit_id: String) -> Dictionary:
	return UNIT_WEAPONS.get(unit_id, {})

# Get weapon profile
static func get_weapon_profile(weapon_id: String) -> Dictionary:
	return WEAPON_PROFILES.get(weapon_id, {})
