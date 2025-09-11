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
	var weapon_profile = get_weapon_profile(weapon_id, board)
	if weapon_profile.is_empty():
		result.log_text = "Unknown weapon: " + weapon_id
		return result
	
	# Calculate total attacks
	var attacks_per_model = weapon_profile.get("attacks", 1)
	var total_attacks = model_ids.size() * attacks_per_model
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
		else:
			var weapon_profile = get_weapon_profile(weapon_id, board)
			if weapon_profile.is_empty():
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
			if weapon_id != "":
				var weapon_profile = get_weapon_profile(weapon_id, board)
				if not weapon_profile.is_empty():
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
	var weapon_profile = get_weapon_profile(weapon_id, board)
	
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
	# Check terrain features for line of sight blocking
	var terrain_features = board.get("terrain_features", [])
	
	for terrain_piece in terrain_features:
		# Only tall terrain (>5") blocks LoS completely
		if terrain_piece.get("height_category", "") == "tall":
			var polygon = terrain_piece.get("polygon", PackedVector2Array())
			if _segment_intersects_polygon(from_pos, to_pos, polygon):
				# Check if both models are outside the terrain
				# (models inside can see out and be seen)
				if not _point_in_polygon(from_pos, polygon) and not _point_in_polygon(to_pos, polygon):
					return false
	
	return true

static func _segment_intersects_polygon(seg_start: Vector2, seg_end: Vector2, poly) -> bool:
	# Use Godot's Geometry2D for proper polygon intersection
	var polygon_packed: PackedVector2Array
	
	if poly is PackedVector2Array:
		polygon_packed = poly
	elif poly is Array:
		# Convert Array to PackedVector2Array
		polygon_packed = PackedVector2Array()
		for vertex in poly:
			if vertex is Dictionary:
				polygon_packed.append(Vector2(vertex.get("x", 0), vertex.get("y", 0)))
			elif vertex is Vector2:
				polygon_packed.append(vertex)
	else:
		return false
	
	if polygon_packed.is_empty():
		return false
	
	# Check if line segment intersects any edge of the polygon
	for i in range(polygon_packed.size()):
		var edge_start = polygon_packed[i]
		var edge_end = polygon_packed[(i + 1) % polygon_packed.size()]
		
		if Geometry2D.segment_intersects_segment(seg_start, seg_end, edge_start, edge_end):
			return true
	
	return false

# Helper function to check if a point is inside a polygon
static func _point_in_polygon(point: Vector2, poly) -> bool:
	var polygon_packed: PackedVector2Array
	
	if poly is PackedVector2Array:
		polygon_packed = poly
	elif poly is Array:
		# Convert Array to PackedVector2Array
		polygon_packed = PackedVector2Array()
		for vertex in poly:
			if vertex is Dictionary:
				polygon_packed.append(Vector2(vertex.get("x", 0), vertex.get("y", 0)))
			elif vertex is Vector2:
				polygon_packed.append(vertex)
	else:
		return false
	
	return Geometry2D.is_point_in_polygon(point, polygon_packed)

# ==========================================
# COVER SYSTEM
# ==========================================

# Check if a target position has benefit of cover from a shooter position
static func check_benefit_of_cover(target_pos: Vector2, shooter_pos: Vector2, board: Dictionary) -> bool:
	var terrain_features = board.get("terrain_features", [])
	
	for terrain_piece in terrain_features:
		if terrain_piece.get("type", "") != "ruins":
			continue
		
		var polygon = terrain_piece.get("polygon", PackedVector2Array())
		if polygon.is_empty():
			continue
		
		# Target within terrain gets cover
		if _point_in_polygon(target_pos, polygon):
			return true
		
		# Target behind terrain (LoS crosses terrain)
		if _segment_intersects_polygon(shooter_pos, target_pos, polygon):
			# Check if shooter is not inside the same terrain piece
			if not _point_in_polygon(shooter_pos, polygon):
				return true
	
	return false

# Check if any models in a unit have cover from the shooting unit
static func check_unit_has_cover(target_unit_id: String, shooter_unit_id: String, board: Dictionary) -> bool:
	var units = board.get("units", {})
	var target_unit = units.get(target_unit_id, {})
	var shooter_unit = units.get(shooter_unit_id, {})
	
	if target_unit.is_empty() or shooter_unit.is_empty():
		return false
	
	# Get average shooter position (simplified)
	var shooter_positions = []
	for model in shooter_unit.get("models", []):
		if model.get("alive", true):
			var pos = _get_model_position(model)
			if pos != Vector2.ZERO:
				shooter_positions.append(pos)
	
	if shooter_positions.is_empty():
		return false
	
	var avg_shooter_pos = Vector2.ZERO
	for pos in shooter_positions:
		avg_shooter_pos += pos
	avg_shooter_pos /= shooter_positions.size()
	
	# Check if majority of target models have cover
	var models_in_cover = 0
	var total_alive_models = 0
	
	for model in target_unit.get("models", []):
		if model.get("alive", true):
			total_alive_models += 1
			var model_pos = _get_model_position(model)
			if model_pos != Vector2.ZERO:
				if check_benefit_of_cover(model_pos, avg_shooter_pos, board):
					models_in_cover += 1
	
	# Unit has cover if majority of models are in cover
	return models_in_cover > (total_alive_models / 2.0)

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
	# Check if model has benefit of cover from ruins terrain
	var model_pos = _get_model_position(model)
	if not model_pos:
		return false
	
	var units = board.get("units", {})
	var shooting_unit = units.get(shooting_unit_id, {})
	
	if shooting_unit.is_empty():
		return false
	
	# Get average shooter position for cover determination
	var shooter_positions = []
	for shooter in shooting_unit.get("models", []):
		if shooter.get("alive", true):
			var shooter_pos = _get_model_position(shooter)
			if shooter_pos != Vector2.ZERO:
				shooter_positions.append(shooter_pos)
	
	if shooter_positions.is_empty():
		return false
	
	# Use average shooter position for cover check
	var avg_shooter_pos = Vector2.ZERO
	for pos in shooter_positions:
		avg_shooter_pos += pos
	avg_shooter_pos /= shooter_positions.size()
	
	# Check if model has benefit of cover using our new cover system
	return check_benefit_of_cover(model_pos, avg_shooter_pos, board)


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
		var unit_weapons = get_unit_weapons(actor_unit_id, board)
		
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
static func get_unit_weapons(unit_id: String, board: Dictionary = {}) -> Dictionary:
	# First try legacy format for backward compatibility
	if UNIT_WEAPONS.has(unit_id):
		return UNIT_WEAPONS.get(unit_id, {})
	
	# Get unit from provided board or current game state
	var units = {}
	if not board.is_empty():
		units = board.get("units", {})
	else:
		units = GameState.state.get("units", {})
	var unit = units.get(unit_id, {})
	
	if unit.is_empty():
		print("WARNING: Unit not found: ", unit_id)
		return {}
	
	# Convert modern weapons format to model-weapon mapping
	var weapons = unit.get("meta", {}).get("weapons", [])
	var models = unit.get("models", [])
	var result = {}
	
	# Assign all weapons to all alive models (simplified approach)
	for model in models:
		var model_id = model.get("id", "")
		if model_id != "" and model.get("alive", true):
			result[model_id] = []
			for weapon in weapons:
				if weapon.get("type", "") == "Ranged":  # Only include ranged weapons for shooting
					var weapon_id = _generate_weapon_id(weapon.get("name", ""))
					result[model_id].append(weapon_id)
	
	return result

# Helper function to generate consistent weapon IDs from names
static func _generate_weapon_id(weapon_name: String) -> String:
	# Convert weapon name to consistent ID format
	var weapon_id = weapon_name.to_lower()
	weapon_id = weapon_id.replace(" ", "_")
	weapon_id = weapon_id.replace("-", "_")
	weapon_id = weapon_id.replace("–", "_")  # Handle em dash
	weapon_id = weapon_id.replace("'", "")
	return weapon_id

# Get weapon profile
static func get_weapon_profile(weapon_id: String, board: Dictionary = {}) -> Dictionary:
	# First try legacy weapon profiles
	if WEAPON_PROFILES.has(weapon_id):
		return WEAPON_PROFILES.get(weapon_id, {})
	
	# Search through all units for matching weapon
	var units = {}
	if not board.is_empty():
		units = board.get("units", {})
	else:
		units = GameState.state.get("units", {})
	
	for unit_id in units:
		var unit = units[unit_id]
		var weapons = unit.get("meta", {}).get("weapons", [])
		
		for weapon in weapons:
			var weapon_name = weapon.get("name", "")
			var generated_id = _generate_weapon_id(weapon_name)
			
			
			if generated_id == weapon_id:
				# Convert weapon format to profile format expected by UI
				# Convert string values to appropriate types where needed
				var weapon_range = weapon.get("range", "0")
				var range_value = 0
				if weapon_range == "Melee":
					range_value = 0
				else:
					range_value = int(weapon_range) if (weapon_range != null and weapon_range.is_valid_int()) else 0
				
				# Helper function to safely convert weapon stat strings to integers
				var attacks_str = weapon.get("attacks", "1")
				var attacks_value = int(attacks_str) if (attacks_str != null and attacks_str.is_valid_int()) else 1
				
				var bs_str = weapon.get("ballistic_skill", "4") 
				var bs_value = int(bs_str) if (bs_str != null and bs_str.is_valid_int()) else 4
				
				var ws_str = weapon.get("weapon_skill", "4")
				var ws_value = int(ws_str) if (ws_str != null and ws_str.is_valid_int()) else 4
				
				var strength_str = weapon.get("strength", "3")
				var strength_value = int(strength_str) if (strength_str != null and strength_str.is_valid_int()) else 3
				
				var ap_str = weapon.get("ap", "0")  
				var ap_value = 0
				if ap_str.begins_with("-"):
					var ap_num_str = ap_str.substr(1)  # Remove the "-"
					ap_value = -int(ap_num_str) if (ap_num_str != null and ap_num_str.is_valid_int()) else 0
				else:
					ap_value = int(ap_str) if (ap_str != null and ap_str.is_valid_int()) else 0
				
				var damage_str = weapon.get("damage", "1")
				var damage_value = int(damage_str) if (damage_str != null and damage_str.is_valid_int()) else 1
				# TODO: Handle complex damage like "D6+2" - for now treat as 1
				
				return {
					"name": weapon_name,
					"type": weapon.get("type", ""),
					"range": range_value,  # Convert to int for calculations
					"attacks": attacks_value,  # Convert to int for calculations
					"bs": bs_value,  # Convert to int for to-hit rolls  
					"ballistic_skill": bs_str,  # Keep string for UI display
					"ws": ws_value,  # Convert to int for melee rolls
					"weapon_skill": ws_str,  # Keep string for UI display
					"strength": strength_value,  # Convert to int for calculations
					"ap": ap_value,  # Convert to int for calculations
					"damage": damage_value,  # Convert to int for calculations
					"special_rules": weapon.get("special_rules", "")
				}
	
	print("WARNING: Weapon profile not found: ", weapon_id)
	return {}

# Validation function to check if unit has weapons
static func unit_has_weapons(unit_id: String) -> bool:
	var unit_weapons = get_unit_weapons(unit_id)
	
	for model_id in unit_weapons:
		if not unit_weapons[model_id].is_empty():
			return true
	
	return false

# Debug function to list all weapons for a unit
static func debug_unit_weapons(unit_id: String) -> void:
	print("=== DEBUGGING WEAPONS FOR UNIT: ", unit_id, " ===")
	
	var unit_weapons = get_unit_weapons(unit_id)
	if unit_weapons.is_empty():
		print("NO WEAPONS FOUND")
		return
	
	for model_id in unit_weapons:
		print("Model ", model_id, ":")
		for weapon_id in unit_weapons[model_id]:
			var profile = get_weapon_profile(weapon_id)
			print("  - ", weapon_id, " (", profile.get("name", "Unknown"), ")")
	
	print("=== END WEAPON DEBUG ===")

# ==========================================
# CHARGE PHASE HELPERS
# ==========================================

# Check if unit is eligible to charge
static func eligible_to_charge(unit_id: String, board: Dictionary) -> bool:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	
	if unit.is_empty():
		return false
	
	var status = unit.get("status", 0)
	var flags = unit.get("flags", {})
	
	# Check if unit is deployed
	if not (status == GameStateData.UnitStatus.DEPLOYED or 
			status == GameStateData.UnitStatus.MOVED or 
			status == GameStateData.UnitStatus.SHOT):
		return false
	
	# Check restriction flags
	if flags.get("cannot_charge", false):
		return false
	
	if flags.get("advanced", false):
		return false
	
	if flags.get("fell_back", false):
		return false
	
	if flags.get("charged_this_turn", false):
		return false
	
	# Check if unit has AIRCRAFT keyword (cannot charge)
	var keywords = unit.get("meta", {}).get("keywords", [])
	if "AIRCRAFT" in keywords:
		return false
	
	# Check if already in engagement range (cannot declare charges)
	if _is_unit_in_engagement_range_charge(unit, board):
		return false
	
	# Check if unit has any alive models
	var has_alive = false
	for model in unit.get("models", []):
		if model.get("alive", true):
			has_alive = true
			break
	
	return has_alive

# Get eligible charge targets within 12" for a unit
static func charge_targets_within_12(unit_id: String, board: Dictionary) -> Dictionary:
	var eligible = {}
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	
	if unit.is_empty():
		return eligible
	
	var unit_owner = unit.get("owner", 0)
	
	# Check each potential target unit
	for target_id in units:
		var target_unit = units[target_id]
		
		# Skip friendly units
		if target_unit.get("owner", 0) == unit_owner:
			continue
		
		# Skip destroyed units
		var has_alive_models = false
		for model in target_unit.get("models", []):
			if model.get("alive", true):
				has_alive_models = true
				break
		
		if not has_alive_models:
			continue
		
		# Check if within 12" charge range
		if _is_target_within_charge_range_rules(unit_id, target_id, board):
			eligible[target_id] = {
				"name": target_unit.get("meta", {}).get("name", target_id),
				"distance": _get_min_distance_to_target_rules(unit_id, target_id, board)
			}
	
	return eligible

# Master validation function for charge paths
static func validate_charge_paths(unit_id: String, targets: Array, roll: int, paths: Dictionary, board: Dictionary) -> Dictionary:
	var errors = []
	var auto_fix_suggestions = []
	
	# 1. Validate path distances
	for model_id in paths:
		var path = paths[model_id]
		if path is Array and path.size() >= 2:
			var path_distance = Measurement.distance_polyline_inches(path)
			if path_distance > roll:
				errors.append("Model %s path exceeds charge distance: %.1f\" > %d\"" % [model_id, path_distance, roll])
				auto_fix_suggestions.append("Reduce path length for model %s" % model_id)
	
	# 2. Validate engagement range with ALL targets
	var engagement_validation = _validate_engagement_range_constraints_rules(unit_id, paths, targets, board)
	if not engagement_validation.valid:
		errors.append_array(engagement_validation.errors)
		auto_fix_suggestions.append("Adjust final positions to reach all targets")
	
	# 3. Validate unit coherency
	var coherency_validation = _validate_unit_coherency_for_charge_rules(unit_id, paths, board)
	if not coherency_validation.valid:
		errors.append_array(coherency_validation.errors)
		auto_fix_suggestions.append("Move models closer together to maintain coherency")
	
	# 4. Validate base-to-base if possible
	var base_to_base_validation = _validate_base_to_base_possible_rules(unit_id, paths, targets, board)
	if not base_to_base_validation.valid:
		errors.append_array(base_to_base_validation.errors)
		auto_fix_suggestions.append("Move models to achieve base-to-base contact when possible")
	
	return {
		"valid": errors.is_empty(),
		"reasons": errors,
		"auto_fix_suggestions": auto_fix_suggestions
	}

# Helper function to check if unit is in engagement range
static func _is_unit_in_engagement_range_charge(unit: Dictionary, board: Dictionary) -> bool:
	const ENGAGEMENT_RANGE_INCHES = 1.0
	var unit_id = unit.get("id", "")
	var models = unit.get("models", [])
	var unit_owner = unit.get("owner", 0)
	var all_units = board.get("units", {})
	
	for model in models:
		if not model.get("alive", true):
			continue
		
		var model_pos = _get_model_position_rules(model)
		if model_pos == null:
			continue
		
		var model_radius = Measurement.base_radius_px(model.get("base_mm", 32))
		var er_px = Measurement.inches_to_px(ENGAGEMENT_RANGE_INCHES)
		
		# Check against all enemy models
		for enemy_unit_id in all_units:
			var enemy_unit = all_units[enemy_unit_id]
			if enemy_unit.get("owner", 0) == unit_owner:
				continue  # Skip friendly units
			
			for enemy_model in enemy_unit.get("models", []):
				if not enemy_model.get("alive", true):
					continue
				
				var enemy_pos = _get_model_position_rules(enemy_model)
				if enemy_pos == null:
					continue
				
				var enemy_radius = Measurement.base_radius_px(enemy_model.get("base_mm", 32))
				var edge_distance = model_pos.distance_to(enemy_pos) - model_radius - enemy_radius
				
				if edge_distance <= er_px:
					return true
	
	return false

# Check if target is within 12" charge range
static func _is_target_within_charge_range_rules(unit_id: String, target_id: String, board: Dictionary) -> bool:
	const CHARGE_RANGE_INCHES = 12.0
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	var target = units.get(target_id, {})
	
	if unit.is_empty() or target.is_empty():
		return false
	
	# Find closest edge-to-edge distance between any models
	var min_distance = INF
	
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		
		var model_pos = _get_model_position_rules(model)
		if model_pos == null:
			continue
		
		var model_radius = Measurement.base_radius_px(model.get("base_mm", 32))
		
		for target_model in target.get("models", []):
			if not target_model.get("alive", true):
				continue
			
			var target_pos = _get_model_position_rules(target_model)
			if target_pos == null:
				continue
			
			var target_radius = Measurement.base_radius_px(target_model.get("base_mm", 32))
			var edge_distance = Measurement.edge_to_edge_distance_px(model_pos, model_radius, target_pos, target_radius)
			var distance_inches = Measurement.px_to_inches(edge_distance)
			
			min_distance = min(min_distance, distance_inches)
	
	return min_distance <= CHARGE_RANGE_INCHES

# Get minimum distance to target
static func _get_min_distance_to_target_rules(unit_id: String, target_id: String, board: Dictionary) -> float:
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	var target = units.get(target_id, {})
	var min_distance = INF
	
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		
		var model_pos = _get_model_position_rules(model)
		if model_pos == null:
			continue
		
		for target_model in target.get("models", []):
			if not target_model.get("alive", true):
				continue
			
			var target_pos = _get_model_position_rules(target_model)
			if target_pos == null:
				continue
			
			var distance = Measurement.distance_inches(model_pos, target_pos)
			min_distance = min(min_distance, distance)
	
	return min_distance

# Helper to get model position for charge calculations
static func _get_model_position_rules(model: Dictionary) -> Vector2:
	var pos = model.get("position")
	if pos == null:
		return Vector2.ZERO
	if pos is Dictionary:
		return Vector2(pos.get("x", 0), pos.get("y", 0))
	elif pos is Vector2:
		return pos
	return Vector2.ZERO

# Validate engagement range constraints for charge
static func _validate_engagement_range_constraints_rules(unit_id: String, per_model_paths: Dictionary, target_ids: Array, board: Dictionary) -> Dictionary:
	const ENGAGEMENT_RANGE_INCHES = 1.0
	var errors = []
	var er_px = Measurement.inches_to_px(ENGAGEMENT_RANGE_INCHES)
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	var unit_owner = unit.get("owner", 0)
	
	# Check that unit ends within ER of ALL targets
	for target_id in target_ids:
		var target_unit = units.get(target_id, {})
		if target_unit.is_empty():
			continue
		
		var unit_in_er_of_target = false
		
		for model_id in per_model_paths:
			var path = per_model_paths[model_id]
			if path is Array and path.size() > 0:
				var final_pos = Vector2(path[-1][0], path[-1][1])
				var model = _get_model_in_unit_rules(unit, model_id)
				var model_radius = Measurement.base_radius_px(model.get("base_mm", 32))
				
				# Check if this model is in ER of any target model
				for target_model in target_unit.get("models", []):
					if not target_model.get("alive", true):
						continue
					
					var target_pos = _get_model_position_rules(target_model)
					if target_pos == null:
						continue
					
					var target_radius = Measurement.base_radius_px(target_model.get("base_mm", 32))
					var edge_distance = final_pos.distance_to(target_pos) - model_radius - target_radius
					
					if edge_distance <= er_px:
						unit_in_er_of_target = true
						break
				
				if unit_in_er_of_target:
					break
		
		if not unit_in_er_of_target:
			var target_name = target_unit.get("meta", {}).get("name", target_id)
			errors.append("Must end within engagement range of all targets: " + target_name)
	
	# Check that unit does NOT end in ER of non-target enemies
	for enemy_unit_id in units:
		var enemy_unit = units[enemy_unit_id]
		if enemy_unit.get("owner", 0) == unit_owner:
			continue  # Skip friendly
		
		if enemy_unit_id in target_ids:
			continue  # Skip declared targets
		
		# Check if any charging model ends in ER of this non-target
		for model_id in per_model_paths:
			var path = per_model_paths[model_id]
			if path is Array and path.size() > 0:
				var final_pos = Vector2(path[-1][0], path[-1][1])
				var model = _get_model_in_unit_rules(unit, model_id)
				var model_radius = Measurement.base_radius_px(model.get("base_mm", 32))
				
				for enemy_model in enemy_unit.get("models", []):
					if not enemy_model.get("alive", true):
						continue
					
					var enemy_pos = _get_model_position_rules(enemy_model)
					if enemy_pos == null:
						continue
					
					var enemy_radius = Measurement.base_radius_px(enemy_model.get("base_mm", 32))
					var edge_distance = final_pos.distance_to(enemy_pos) - model_radius - enemy_radius
					
					if edge_distance <= er_px:
						var enemy_name = enemy_unit.get("meta", {}).get("name", enemy_unit_id)
						errors.append("Cannot end within engagement range of non-target unit: " + enemy_name)
						break
	
	return {"valid": errors.is_empty(), "errors": errors}

# Validate unit coherency for charge
static func _validate_unit_coherency_for_charge_rules(unit_id: String, per_model_paths: Dictionary, board: Dictionary) -> Dictionary:
	var errors = []
	var coherency_distance = 2.0  # 2" coherency in 10e
	var coherency_px = Measurement.inches_to_px(coherency_distance)
	
	var final_positions = []
	
	# Get final positions for all models
	for model_id in per_model_paths:
		var path = per_model_paths[model_id]
		if path is Array and path.size() > 0:
			final_positions.append(Vector2(path[-1][0], path[-1][1]))
	
	if final_positions.size() < 2:
		return {"valid": true, "errors": []}  # Single model or no movement
	
	# Check that each model is within 2" of at least one other model
	for i in range(final_positions.size()):
		var pos = final_positions[i]
		var has_nearby_model = false
		
		for j in range(final_positions.size()):
			if i == j:
				continue
			
			var other_pos = final_positions[j]
			var distance = pos.distance_to(other_pos)
			
			if distance <= coherency_px:
				has_nearby_model = true
				break
		
		if not has_nearby_model:
			errors.append("Unit coherency broken: model %d too far from other models" % i)
	
	return {"valid": errors.is_empty(), "errors": errors}

# Validate base-to-base if possible for charge (simplified for MVP)
static func _validate_base_to_base_possible_rules(unit_id: String, per_model_paths: Dictionary, target_ids: Array, board: Dictionary) -> Dictionary:
	# For MVP, we'll implement a simplified check
	# In full implementation, this would check if base-to-base contact is achievable
	# and required when all other constraints are satisfied
	return {"valid": true, "errors": []}

# Helper to get model in unit for charge calculations
static func _get_model_in_unit_rules(unit: Dictionary, model_id: String) -> Dictionary:
	var models = unit.get("models", [])
	for model in models:
		if model.get("id", "") == model_id:
			return model
	return {}

# ==========================================
# ARMY LIST WEAPON PARSING
# ==========================================

# Parse weapon stats from army list data
static func parse_weapon_stats(weapon_data: Dictionary) -> Dictionary:
	var stats = {}
	
	# Handle dice notation (e.g., "D6", "2D6")
	if weapon_data.has("attacks"):
		var attacks = weapon_data.get("attacks", "1")
		if attacks is String:
			stats["attacks"] = _parse_dice_notation(attacks)
		else:
			stats["attacks"] = {"min": attacks, "max": attacks, "dice": ""}
	else:
		stats["attacks"] = {"min": 1, "max": 1, "dice": ""}
	
	# Parse other weapon stats
	stats["range"] = _parse_range(weapon_data.get("range", "Melee"))
	stats["weapon_skill"] = weapon_data.get("weapon_skill", null)
	stats["ballistic_skill"] = weapon_data.get("ballistic_skill", null)
	stats["strength"] = _parse_stat_value(weapon_data.get("strength", "4"))
	stats["ap"] = _parse_ap_value(weapon_data.get("ap", "0"))
	stats["damage"] = _parse_damage(weapon_data.get("damage", "1"))
	stats["special_rules"] = weapon_data.get("special_rules", "")
	stats["type"] = weapon_data.get("type", "Ranged")
	
	return stats

static func _parse_dice_notation(notation: String) -> Dictionary:
	if notation == "D3":
		return {"min": 1, "max": 3, "dice": "D3"}
	elif notation == "D6":
		return {"min": 1, "max": 6, "dice": "D6"}
	elif notation.begins_with("D6+"):
		var bonus = notation.split("+")[1].to_int()
		return {"min": 1 + bonus, "max": 6 + bonus, "dice": notation}
	elif notation.begins_with("2D6"):
		return {"min": 2, "max": 12, "dice": "2D6"}
	elif notation.to_int() > 0:
		var value = notation.to_int()
		return {"min": value, "max": value, "dice": ""}
	else:
		# Handle unknown dice notation as 1
		print("Unknown dice notation: ", notation, ", defaulting to 1")
		return {"min": 1, "max": 1, "dice": ""}

static func _parse_range(range_str: String) -> int:
	if range_str == "Melee":
		return 0
	else:
		var value = range_str.to_int()
		return value if value > 0 else 24  # Default to 24" if parsing fails

static func _parse_stat_value(stat_str: String) -> int:
	var value = stat_str.to_int()
	return value if value > 0 else 4  # Default to 4 if parsing fails

static func _parse_ap_value(ap_str: String) -> int:
	if ap_str.begins_with("-"):
		return ap_str.to_int()
	elif ap_str == "0":
		return 0
	else:
		var value = ap_str.to_int()
		return -value if value > 0 else 0

static func _parse_damage(damage_str: String) -> Dictionary:
	if damage_str == "D3":
		return {"min": 1, "max": 3, "dice": "D3"}
	elif damage_str == "D6":
		return {"min": 1, "max": 6, "dice": "D6"}
	elif damage_str.begins_with("D6+"):
		var bonus = damage_str.split("+")[1].to_int()
		return {"min": 1 + bonus, "max": 6 + bonus, "dice": damage_str}
	elif damage_str.begins_with("D3+"):
		var bonus = damage_str.split("+")[1].to_int()
		return {"min": 1 + bonus, "max": 3 + bonus, "dice": damage_str}
	else:
		var value = damage_str.to_int()
		if value > 0:
			return {"min": value, "max": value, "dice": ""}
		else:
			# Handle unknown damage notation as 1
			print("Unknown damage notation: ", damage_str, ", defaulting to 1")
			return {"min": 1, "max": 1, "dice": ""}

# Get parsed weapon stats for a unit
static func get_unit_parsed_weapons(unit_id: String) -> Array:
	if not GameState:
		return []
		
	var unit = GameState.get_unit(unit_id)
	if unit.is_empty():
		return []
	
	var parsed_weapons = []
	var weapons = unit.get("meta", {}).get("weapons", [])
	
	for weapon in weapons:
		var parsed = parse_weapon_stats(weapon)
		parsed["name"] = weapon.get("name", "Unknown Weapon")
		parsed_weapons.append(parsed)
	
	return parsed_weapons

# Validate weapon special rules
static func validate_weapon_special_rules(special_rules: String) -> Dictionary:
	var result = {"valid": true, "errors": []}
	
	if special_rules.is_empty():
		return result
	
	# Split by comma to handle multiple rules
	var rules_list = special_rules.split(",")
	
	for rule in rules_list:
		var rule_name = rule.strip_edges().to_lower()
		
		# Check against known special rules (expand this list as needed)
		var known_rules = [
			"assault", "heavy", "rapid fire", "pistol", "torrent", "blast",
			"precision", "sustained hits", "devastating wounds", "lethal hits",
			"twin-linked", "ignores cover", "lance", "anti-infantry",
			"anti-vehicle", "anti-monster", "feel no pain"
		]
		
		var rule_recognized = false
		for known_rule in known_rules:
			if rule_name.contains(known_rule):
				rule_recognized = true
				break
		
		if not rule_recognized:
			print("Warning: Unknown weapon special rule: ", rule_name)
			# Don't mark as invalid, just warn
	
	return result

# ===== MELEE COMBAT FUNCTIONS =====

# Main melee combat resolution entry point
static func resolve_melee_attacks(action: Dictionary, board: Dictionary, rng_service: RNGService = null) -> Dictionary:
	if not rng_service:
		rng_service = RNGService.new()
	
	var result = {
		"success": true,
		"phase": "FIGHT",
		"diffs": [],
		"dice": [],
		"log_text": ""
	}
	
	var actor_unit_id = action.get("actor_unit_id", "")
	var assignments = action.get("payload", {}).get("assignments", [])
	
	if assignments.is_empty():
		result.success = false
		result.log_text = "No attack assignments provided"
		return result
	
	var units = board.get("units", {})
	var actor_unit = units.get(actor_unit_id, {})
	
	if actor_unit.is_empty():
		result.success = false
		result.log_text = "Actor unit not found"
		return result
	
	# Process each attack assignment
	for assignment in assignments:
		var assignment_result = _resolve_melee_assignment(assignment, actor_unit_id, board, rng_service)
		result.diffs.append_array(assignment_result.diffs)
		result.dice.append_array(assignment_result.dice)
		if assignment_result.log_text:
			result.log_text += assignment_result.log_text + "\n"
	
	return result

# Resolve a single melee assignment (models with weapon -> target)
static func _resolve_melee_assignment(assignment: Dictionary, actor_unit_id: String, board: Dictionary, rng: RNGService) -> Dictionary:
	var result = {
		"diffs": [],
		"dice": [],
		"log_text": ""
	}
	
	var attacker_id = assignment.get("attacker", "")
	var target_id = assignment.get("target", "")
	var weapon_id = assignment.get("weapon", "")
	var attacking_models = assignment.get("models", [])
	
	if weapon_id.is_empty():
		result.log_text = "No weapon specified for melee attack"
		return result
	
	# Get weapon profile (melee weapons use same format as ranged)
	var weapon = get_weapon_profile(weapon_id)
	if weapon.is_empty():
		result.log_text = "Weapon profile not found: " + weapon_id
		return result
	
	var units = board.get("units", {})
	var attacker_unit = units.get(attacker_id, {})
	var target_unit = units.get(target_id, {})
	
	if attacker_unit.is_empty() or target_unit.is_empty():
		result.log_text = "Attacker or target unit not found"
		return result
	
	# Calculate total attacks
	var total_attacks = 0
	var attacker_models = attacker_unit.get("models", [])
	
	for model_index in range(attacker_models.size()):
		var model = attacker_models[model_index]
		if not model.get("alive", true):
			continue
			
		# If specific models assigned, check if this model is included
		if not attacking_models.is_empty() and not str(model_index) in attacking_models:
			continue
		
		# Add attacks from this model
		var weapon_attacks = weapon.get("attacks", 1)
		total_attacks += weapon_attacks
	
	if total_attacks == 0:
		result.log_text = "No valid attacking models"
		return result
	
	# Get combat stats
	var attacker_stats = attacker_unit.get("meta", {}).get("stats", {})
	var target_stats = target_unit.get("meta", {}).get("stats", {})
	
	var weapon_skill = attacker_stats.get("weapon_skill", 4)
	var strength = weapon.get("strength", attacker_stats.get("strength", 3))
	var toughness = target_stats.get("toughness", 4)
	var ap = weapon.get("ap", 0)
	var damage = weapon.get("damage", 1)
	var armor_save = target_stats.get("save", 6)
	
	# Roll to hit (using Weapon Skill instead of Ballistic Skill)
	var hit_rolls = rng.roll_d6(total_attacks)
	var hits = 0
	for roll in hit_rolls:
		var success = roll >= weapon_skill
		if success:
			hits += 1
		result.dice.append({
			"context": "hit_roll_melee",
			"roll": roll,
			"target": weapon_skill,
			"success": success,
			"weapon": weapon_id
		})
	
	if hits == 0:
		result.log_text = "Melee: %d attacks, 0 hits" % total_attacks
		return result
	
	# Roll to wound (same logic as shooting)
	var wound_target = _calculate_wound_threshold(strength, toughness)
	var wound_rolls = rng.roll_d6(hits)
	var wounds = 0
	for roll in wound_rolls:
		var success = roll >= wound_target
		if success:
			wounds += 1
		result.dice.append({
			"context": "wound_roll",
			"roll": roll,
			"target": wound_target,
			"success": success,
			"strength": strength,
			"toughness": toughness
		})
	
	if wounds == 0:
		result.log_text = "Melee: %d attacks, %d hits, 0 wounds" % [total_attacks, hits]
		return result
	
	# Apply armor saves (same logic as shooting)
	var modified_save = armor_save - ap
	var save_rolls = rng.roll_d6(wounds)
	var failed_saves = 0
	for roll in save_rolls:
		var success = roll >= modified_save
		if not success:
			failed_saves += 1
		result.dice.append({
			"context": "save_roll",
			"roll": roll,
			"target": modified_save,
			"success": success,
			"ap": ap,
			"original_save": armor_save
		})
	
	if failed_saves == 0:
		result.log_text = "Melee: %d attacks, %d hits, %d wounds, 0 failed saves" % [total_attacks, hits, wounds]
		return result
	
	# Apply damage to target unit
	var damage_result = _apply_damage_to_unit(target_id, failed_saves, damage, board, rng)
	result.diffs.append_array(damage_result.diffs)
	
	result.log_text = "Melee: %d attacks, %d hits, %d wounds, %d casualties" % [total_attacks, hits, wounds, damage_result.casualties]
	
	return result

# Get fight priority for unit
static func get_fight_priority(unit: Dictionary) -> int:
	# Check if unit charged this turn
	if unit.get("flags", {}).get("charged_this_turn", false):
		return 0  # FIGHTS_FIRST
	
	# Check for Fights First ability
	var abilities = unit.get("meta", {}).get("abilities", [])
	for ability in abilities:
		if "fights_first" in str(ability).to_lower():
			return 0  # FIGHTS_FIRST
	
	# Check for Fights Last debuff
	var status_effects = unit.get("status_effects", {})
	if status_effects.get("fights_last", false):
		return 2  # FIGHTS_LAST
	
	return 1  # NORMAL

# Check if two models are in engagement range
static func is_in_engagement_range(model1_pos: Vector2, model2_pos: Vector2, base1_mm: float = 25.0, base2_mm: float = 25.0) -> bool:
	# Calculate edge-to-edge distance
	var center_distance_mm = model1_pos.distance_to(model2_pos)
	var base_separation = (base1_mm + base2_mm) / 2.0
	var edge_distance_mm = center_distance_mm - base_separation
	
	# 1" engagement range (25.4mm)
	return edge_distance_mm <= 25.4

# Check if any models from two units are in engagement range
static func units_in_engagement_range(unit1: Dictionary, unit2: Dictionary) -> bool:
	var models1 = unit1.get("models", [])
	var models2 = unit2.get("models", [])
	
	for model1 in models1:
		if not model1.get("alive", true):
			continue
		
		var pos1_data = model1.get("position", {})
		var pos1 = Vector2(pos1_data.get("x", 0), pos1_data.get("y", 0))
		var base1_mm = model1.get("base_mm", 25.0)
		
		for model2 in models2:
			if not model2.get("alive", true):
				continue
			
			var pos2_data = model2.get("position", {})
			var pos2 = Vector2(pos2_data.get("x", 0), pos2_data.get("y", 0))
			var base2_mm = model2.get("base_mm", 25.0)
			
			if is_in_engagement_range(pos1, pos2, base1_mm, base2_mm):
				return true
	
	return false

# Get melee weapons for a unit
static func get_unit_melee_weapons(unit_id: String, board: Dictionary = {}) -> Dictionary:
	var unit_weapons = {}
	
	# Use provided board or get from GameState
	var units = {}
	if not board.is_empty():
		units = board.get("units", {})
	else:
		units = GameState.state.get("units", {})
	
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return unit_weapons
	
	var models = unit.get("models", [])
	
	for model_index in range(models.size()):
		var model = models[model_index]
		if not model.get("alive", true):
			continue
		
		var model_id = "m" + str(model_index)
		var model_weapons = []
		
		# Get weapons from model or unit meta
		var weapons_data = unit.get("meta", {}).get("weapons", [])
		
		for weapon in weapons_data:
			# Check if this is a melee weapon
			if weapon.get("type", "").to_lower() == "melee":
				model_weapons.append(weapon.get("name", "Unknown Weapon"))
		
		if not model_weapons.is_empty():
			unit_weapons[model_id] = model_weapons
	
	return unit_weapons

# Helper function to apply damage to a unit (reused from shooting)
static func _apply_damage_to_unit(unit_id: String, failed_saves: int, damage_per_wound: int, board: Dictionary, rng: RNGService) -> Dictionary:
	var result = {"diffs": [], "casualties": 0}
	
	var units = board.get("units", {})
	var unit = units.get(unit_id, {})
	if unit.is_empty():
		return result
	
	var models = unit.get("models", [])
	var wounds_to_allocate = failed_saves
	
	# Simple damage allocation - apply to first alive model
	for model_index in range(models.size()):
		if wounds_to_allocate <= 0:
			break
			
		var model = models[model_index]
		if not model.get("alive", true):
			continue
		
		var current_wounds = model.get("current_wounds", model.get("wounds", 1))
		var max_wounds = model.get("wounds", 1)
		
		# Apply damage
		var wounds_dealt = min(wounds_to_allocate, damage_per_wound)
		var new_wounds = current_wounds - wounds_dealt
		
		if new_wounds <= 0:
			# Model dies
			result.diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.alive" % [unit_id, model_index],
				"value": false
			})
			result.diffs.append({
				"op": "set", 
				"path": "units.%s.models.%d.current_wounds" % [unit_id, model_index],
				"value": 0
			})
			result.casualties += 1
			wounds_to_allocate -= 1
		else:
			# Model survives with reduced wounds
			result.diffs.append({
				"op": "set",
				"path": "units.%s.models.%d.current_wounds" % [unit_id, model_index],
				"value": new_wounds
			})
			wounds_to_allocate -= 1
	
	return result
