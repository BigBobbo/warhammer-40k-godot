extends RefCounted
class_name DeploymentZoneData

# DeploymentZoneData - Static data for all deployment zone types and their objective positions
# All coordinates are in INCHES on a 44" x 60" board. Origin is top-left (0,0).
# Consumers convert to pixels via Measurement.inches_to_px().
#
# Data is loaded from JSON files in res://deployment_zones/ when available,
# falling back to hardcoded definitions otherwise.

# Board dimensions in inches
const BOARD_WIDTH: float = 44.0
const BOARD_HEIGHT: float = 60.0

# All supported deployment types
const DEPLOYMENT_TYPES = [
	"hammer_anvil",
	"dawn_of_war",
	"search_and_destroy",
	"sweeping_engagement",
	"crucible_of_battle"
]

# Returns deployment zone polygons for both players (in inches)
# Each zone is an Array of {"x": float, "y": float} dictionaries
static func get_zones(deployment_type: String) -> Array:
	# Try loading from JSON first
	var json_data = _try_load_json(deployment_type)
	if json_data.size() > 0 and json_data.has("zones"):
		print("[DeploymentZoneData] Loaded zones for '%s' from JSON" % deployment_type)
		return json_data["zones"]

	# Fall back to hardcoded definitions
	match deployment_type:
		"hammer_anvil":
			return _hammer_anvil_zones()
		"dawn_of_war":
			return _dawn_of_war_zones()
		"search_and_destroy":
			return _search_and_destroy_zones()
		"sweeping_engagement":
			return _sweeping_engagement_zones()
		"crucible_of_battle":
			return _crucible_of_battle_zones()
		_:
			push_warning("DeploymentZoneData: Unknown deployment type '%s', falling back to hammer_anvil" % deployment_type)
			return _hammer_anvil_zones()

# Returns deployment zone polygons as PackedVector2Array in pixels
# Ready for direct use by visual components and collision checks
static func get_zones_px(deployment_type: String) -> Array:
	var zones_inches = get_zones(deployment_type)
	var zones_px = []
	for zone in zones_inches:
		var poly = PackedVector2Array()
		for point in zone["poly"]:
			poly.append(Vector2(
				Measurement.inches_to_px(point["x"]),
				Measurement.inches_to_px(point["y"])
			))
		zones_px.append({
			"player": zone["player"],
			"poly": poly
		})
	return zones_px

# Returns objective positions for a given deployment type (in inches)
static func get_objectives(deployment_type: String) -> Array:
	# Try loading from JSON first
	var json_data = _try_load_json(deployment_type)
	if json_data.size() > 0 and json_data.has("objectives"):
		# Convert JSON format [x, y] to Vector2
		var objectives = []
		for obj in json_data["objectives"]:
			var pos = obj.get("position", [0, 0])
			objectives.append({
				"id": obj["id"],
				"position_inches": Vector2(pos[0], pos[1]),
				"radius_mm": obj.get("radius_mm", 40),
				"zone": obj.get("zone", "no_mans_land")
			})
		print("[DeploymentZoneData] Loaded objectives for '%s' from JSON" % deployment_type)
		return objectives

	# Fall back to hardcoded definitions
	match deployment_type:
		"hammer_anvil":
			return _hammer_anvil_objectives()
		"dawn_of_war":
			return _dawn_of_war_objectives()
		"search_and_destroy":
			return _search_and_destroy_objectives()
		"sweeping_engagement":
			return _sweeping_engagement_objectives()
		"crucible_of_battle":
			return _crucible_of_battle_objectives()
		_:
			push_warning("DeploymentZoneData: Unknown deployment type '%s', falling back to hammer_anvil" % deployment_type)
			return _hammer_anvil_objectives()

# Returns objective data as pixel-coordinate dictionaries
# Ready for direct use by MissionManager
static func get_objectives_px(deployment_type: String) -> Array:
	var objectives_inches = get_objectives(deployment_type)
	var objectives_px = []
	for obj in objectives_inches:
		objectives_px.append({
			"id": obj["id"],
			"position": Vector2(
				Measurement.inches_to_px(obj["position_inches"].x),
				Measurement.inches_to_px(obj["position_inches"].y)
			),
			"radius_mm": obj.get("radius_mm", 40),
			"zone": obj.get("zone", "no_mans_land")  # "player1", "player2", or "no_mans_land"
		})
	return objectives_px

# Returns display name for a deployment type
static func get_display_name(deployment_type: String) -> String:
	# Try JSON first for custom names
	var json_data = _try_load_json(deployment_type)
	if json_data.size() > 0 and json_data.has("name"):
		return json_data["name"]

	match deployment_type:
		"hammer_anvil":
			return "Hammer and Anvil"
		"dawn_of_war":
			return "Dawn of War"
		"search_and_destroy":
			return "Search and Destroy"
		"sweeping_engagement":
			return "Sweeping Engagement"
		"crucible_of_battle":
			return "Crucible of Battle"
		_:
			return deployment_type

# ============================================================
# JSON LOADING
# ============================================================

# Cache for loaded JSON data to avoid repeated file reads
static var _json_cache: Dictionary = {}

static func _try_load_json(deployment_type: String) -> Dictionary:
	# Check cache first
	if _json_cache.has(deployment_type):
		return _json_cache[deployment_type]

	var json_path = "res://deployment_zones/%s.json" % deployment_type
	if not FileAccess.file_exists(json_path):
		_json_cache[deployment_type] = {}
		return {}

	var file = FileAccess.open(json_path, FileAccess.READ)
	if not file:
		print("[DeploymentZoneData] Failed to open JSON file: ", json_path)
		_json_cache[deployment_type] = {}
		return {}

	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()

	if parse_result != OK:
		print("[DeploymentZoneData] Failed to parse JSON '%s': %s at line %d" % [json_path, json.get_error_message(), json.get_error_line()])
		_json_cache[deployment_type] = {}
		return {}

	var data = json.data
	_json_cache[deployment_type] = data
	return data

# Clear the JSON cache (useful if files are modified at runtime)
static func clear_cache() -> void:
	_json_cache.clear()

# ============================================================
# DEPLOYMENT ZONE DEFINITIONS (HARDCODED FALLBACKS)
# ============================================================

# Hammer and Anvil: Short edges (top/bottom), 12" deep zones
# P1 at top, P2 at bottom, 24" no-man's-land gap
static func _hammer_anvil_zones() -> Array:
	return [
		{
			"player": 1,
			"poly": [
				{"x": 0.0, "y": 0.0},
				{"x": 44.0, "y": 0.0},
				{"x": 44.0, "y": 12.0},
				{"x": 0.0, "y": 12.0}
			]
		},
		{
			"player": 2,
			"poly": [
				{"x": 0.0, "y": 48.0},
				{"x": 44.0, "y": 48.0},
				{"x": 44.0, "y": 60.0},
				{"x": 0.0, "y": 60.0}
			]
		}
	]

# Dawn of War: Long edges (left/right), 12" deep zones
# P1 on left, P2 on right, 20" no-man's-land gap
static func _dawn_of_war_zones() -> Array:
	return [
		{
			"player": 1,
			"poly": [
				{"x": 0.0, "y": 0.0},
				{"x": 12.0, "y": 0.0},
				{"x": 12.0, "y": 60.0},
				{"x": 0.0, "y": 60.0}
			]
		},
		{
			"player": 2,
			"poly": [
				{"x": 32.0, "y": 0.0},
				{"x": 44.0, "y": 0.0},
				{"x": 44.0, "y": 60.0},
				{"x": 32.0, "y": 60.0}
			]
		}
	]

# Search and Destroy: Opposite corner L-shaped zones
# P1 in top-left corner, P2 in bottom-right corner
# Each zone: 24" along each edge, 6" deep, forming an L-shape
static func _search_and_destroy_zones() -> Array:
	return [
		{
			"player": 1,
			"poly": [
				{"x": 0.0, "y": 0.0},
				{"x": 24.0, "y": 0.0},
				{"x": 24.0, "y": 6.0},
				{"x": 6.0, "y": 6.0},
				{"x": 6.0, "y": 24.0},
				{"x": 0.0, "y": 24.0}
			]
		},
		{
			"player": 2,
			"poly": [
				{"x": 20.0, "y": 36.0},
				{"x": 38.0, "y": 36.0},
				{"x": 38.0, "y": 54.0},
				{"x": 44.0, "y": 54.0},
				{"x": 44.0, "y": 60.0},
				{"x": 20.0, "y": 60.0}
			]
		}
	]

# Sweeping Engagement: Stepped zones along long edges (Pariah Nexus version)
# Replaces the original diagonal deployment with a stepped zone
# P1 on left side: 8" deep at edges, stepping to 14" in the middle section
# P2 on right side: mirror of P1
static func _sweeping_engagement_zones() -> Array:
	return [
		{
			"player": 1,
			"poly": [
				{"x": 0.0, "y": 0.0},
				{"x": 8.0, "y": 0.0},
				{"x": 8.0, "y": 12.0},
				{"x": 14.0, "y": 12.0},
				{"x": 14.0, "y": 48.0},
				{"x": 8.0, "y": 48.0},
				{"x": 8.0, "y": 60.0},
				{"x": 0.0, "y": 60.0}
			]
		},
		{
			"player": 2,
			"poly": [
				{"x": 36.0, "y": 0.0},
				{"x": 44.0, "y": 0.0},
				{"x": 44.0, "y": 60.0},
				{"x": 36.0, "y": 60.0},
				{"x": 36.0, "y": 48.0},
				{"x": 30.0, "y": 48.0},
				{"x": 30.0, "y": 12.0},
				{"x": 36.0, "y": 12.0}
			]
		}
	]

# Crucible of Battle: Stepped zones along short edges
# P1 at top: 8" deep at sides, stepping to 14" in the center
# P2 at bottom: mirror of P1
static func _crucible_of_battle_zones() -> Array:
	return [
		{
			"player": 1,
			"poly": [
				{"x": 0.0, "y": 0.0},
				{"x": 44.0, "y": 0.0},
				{"x": 44.0, "y": 8.0},
				{"x": 34.0, "y": 8.0},
				{"x": 34.0, "y": 14.0},
				{"x": 10.0, "y": 14.0},
				{"x": 10.0, "y": 8.0},
				{"x": 0.0, "y": 8.0}
			]
		},
		{
			"player": 2,
			"poly": [
				{"x": 0.0, "y": 52.0},
				{"x": 10.0, "y": 52.0},
				{"x": 10.0, "y": 46.0},
				{"x": 34.0, "y": 46.0},
				{"x": 34.0, "y": 52.0},
				{"x": 44.0, "y": 52.0},
				{"x": 44.0, "y": 60.0},
				{"x": 0.0, "y": 60.0}
			]
		}
	]

# ============================================================
# OBJECTIVE POSITION DEFINITIONS (HARDCODED FALLBACKS)
# ============================================================
# Each deployment map has 5 objectives:
#   - obj_home_1: In or near Player 1's deployment zone
#   - obj_home_2: In or near Player 2's deployment zone
#   - obj_center: Board center
#   - obj_nml_1: No man's land, closer to P1
#   - obj_nml_2: No man's land, closer to P2
#
# Positions are based on standard Chapter Approved deployment cards.
# "zone" indicates which area the objective is in for mission rules
# (e.g., Scorched Earth only allows burning non-home objectives)

# Hammer and Anvil objectives
static func _hammer_anvil_objectives() -> Array:
	return [
		{
			"id": "obj_center",
			"position_inches": Vector2(22.0, 30.0),
			"radius_mm": 40,
			"zone": "no_mans_land"
		},
		{
			"id": "obj_nml_1",
			"position_inches": Vector2(10.0, 18.0),
			"radius_mm": 40,
			"zone": "no_mans_land"
		},
		{
			"id": "obj_nml_2",
			"position_inches": Vector2(34.0, 42.0),
			"radius_mm": 40,
			"zone": "no_mans_land"
		},
		{
			"id": "obj_home_1",
			"position_inches": Vector2(22.0, 6.0),
			"radius_mm": 40,
			"zone": "player1"
		},
		{
			"id": "obj_home_2",
			"position_inches": Vector2(22.0, 54.0),
			"radius_mm": 40,
			"zone": "player2"
		}
	]

# Dawn of War objectives
static func _dawn_of_war_objectives() -> Array:
	return [
		{
			"id": "obj_center",
			"position_inches": Vector2(22.0, 30.0),
			"radius_mm": 40,
			"zone": "no_mans_land"
		},
		{
			"id": "obj_nml_1",
			"position_inches": Vector2(18.0, 15.0),
			"radius_mm": 40,
			"zone": "no_mans_land"
		},
		{
			"id": "obj_nml_2",
			"position_inches": Vector2(26.0, 45.0),
			"radius_mm": 40,
			"zone": "no_mans_land"
		},
		{
			"id": "obj_home_1",
			"position_inches": Vector2(6.0, 30.0),
			"radius_mm": 40,
			"zone": "player1"
		},
		{
			"id": "obj_home_2",
			"position_inches": Vector2(38.0, 30.0),
			"radius_mm": 40,
			"zone": "player2"
		}
	]

# Search and Destroy objectives
static func _search_and_destroy_objectives() -> Array:
	return [
		{
			"id": "obj_center",
			"position_inches": Vector2(22.0, 30.0),
			"radius_mm": 40,
			"zone": "no_mans_land"
		},
		{
			"id": "obj_nml_1",
			"position_inches": Vector2(11.0, 24.0),
			"radius_mm": 40,
			"zone": "no_mans_land"
		},
		{
			"id": "obj_nml_2",
			"position_inches": Vector2(33.0, 36.0),
			"radius_mm": 40,
			"zone": "no_mans_land"
		},
		{
			"id": "obj_home_1",
			"position_inches": Vector2(6.0, 6.0),
			"radius_mm": 40,
			"zone": "player1"
		},
		{
			"id": "obj_home_2",
			"position_inches": Vector2(38.0, 54.0),
			"radius_mm": 40,
			"zone": "player2"
		}
	]

# Sweeping Engagement objectives
static func _sweeping_engagement_objectives() -> Array:
	return [
		{
			"id": "obj_center",
			"position_inches": Vector2(22.0, 30.0),
			"radius_mm": 40,
			"zone": "no_mans_land"
		},
		{
			"id": "obj_nml_1",
			"position_inches": Vector2(18.0, 15.0),
			"radius_mm": 40,
			"zone": "no_mans_land"
		},
		{
			"id": "obj_nml_2",
			"position_inches": Vector2(26.0, 45.0),
			"radius_mm": 40,
			"zone": "no_mans_land"
		},
		{
			"id": "obj_home_1",
			"position_inches": Vector2(7.0, 30.0),
			"radius_mm": 40,
			"zone": "player1"
		},
		{
			"id": "obj_home_2",
			"position_inches": Vector2(37.0, 30.0),
			"radius_mm": 40,
			"zone": "player2"
		}
	]

# Crucible of Battle objectives
static func _crucible_of_battle_objectives() -> Array:
	return [
		{
			"id": "obj_center",
			"position_inches": Vector2(22.0, 30.0),
			"radius_mm": 40,
			"zone": "no_mans_land"
		},
		{
			"id": "obj_nml_1",
			"position_inches": Vector2(10.0, 22.0),
			"radius_mm": 40,
			"zone": "no_mans_land"
		},
		{
			"id": "obj_nml_2",
			"position_inches": Vector2(34.0, 38.0),
			"radius_mm": 40,
			"zone": "no_mans_land"
		},
		{
			"id": "obj_home_1",
			"position_inches": Vector2(22.0, 4.0),
			"radius_mm": 40,
			"zone": "player1"
		},
		{
			"id": "obj_home_2",
			"position_inches": Vector2(22.0, 56.0),
			"radius_mm": 40,
			"zone": "player2"
		}
	]
