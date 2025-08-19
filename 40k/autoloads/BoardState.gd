extends Node

# BoardState - Legacy compatibility layer and visual data provider
# Now primarily handles deployment zone visual data for backwards compatibility

# Legacy enum for backwards compatibility
enum UnitStatus { UNDEPLOYED, DEPLOYING, DEPLOYED }

var deployment_zones: Array = []

# Legacy property that forwards to GameState for backwards compatibility
var active_player: int:
	get:
		return GameState.get_active_player()
	set(value):
		GameState.set_active_player(value)

func _ready() -> void:
	initialize_deployment_zones()

func initialize_deployment_zones() -> void:
	deployment_zones = [
		{
			"player": 1,
			"poly": _get_dawn_of_war_zone_1()
		},
		{
			"player": 2,
			"poly": _get_dawn_of_war_zone_2()
		}
	]

# Legacy data - these are now maintained for visual components that haven't been updated yet
var units: Dictionary = {
		"U_INTERCESSORS_A": {
			"owner": 1,
			"status": UnitStatus.UNDEPLOYED,
			"models": [
				{"id": "m1", "wounds": 2, "base_mm": 32, "pos": null},
				{"id": "m2", "wounds": 2, "base_mm": 32, "pos": null},
				{"id": "m3", "wounds": 2, "base_mm": 32, "pos": null},
				{"id": "m4", "wounds": 2, "base_mm": 32, "pos": null},
				{"id": "m5", "wounds": 2, "base_mm": 32, "pos": null}
			],
			"meta": {
				"name": "Intercessor Squad",
				"keywords": ["INFANTRY", "PRIMARIS", "IMPERIUM", "ADEPTUS ASTARTES"]
			}
		},
		"U_TACTICAL_A": {
			"owner": 1,
			"status": UnitStatus.UNDEPLOYED,
			"models": [
				{"id": "m1", "wounds": 2, "base_mm": 32, "pos": null},
				{"id": "m2", "wounds": 2, "base_mm": 32, "pos": null},
				{"id": "m3", "wounds": 2, "base_mm": 32, "pos": null},
				{"id": "m4", "wounds": 2, "base_mm": 32, "pos": null},
				{"id": "m5", "wounds": 2, "base_mm": 32, "pos": null}
			],
			"meta": {
				"name": "Tactical Squad",
				"keywords": ["INFANTRY", "IMPERIUM", "ADEPTUS ASTARTES"]
			}
		},
		"U_BOYZ_A": {
			"owner": 2,
			"status": UnitStatus.UNDEPLOYED,
			"models": [
				{"id": "m1", "wounds": 1, "base_mm": 32, "pos": null},
				{"id": "m2", "wounds": 1, "base_mm": 32, "pos": null},
				{"id": "m3", "wounds": 1, "base_mm": 32, "pos": null},
				{"id": "m4", "wounds": 1, "base_mm": 32, "pos": null},
				{"id": "m5", "wounds": 1, "base_mm": 32, "pos": null},
				{"id": "m6", "wounds": 1, "base_mm": 32, "pos": null},
				{"id": "m7", "wounds": 1, "base_mm": 32, "pos": null},
				{"id": "m8", "wounds": 1, "base_mm": 32, "pos": null},
				{"id": "m9", "wounds": 1, "base_mm": 32, "pos": null},
				{"id": "m10", "wounds": 1, "base_mm": 32, "pos": null}
			],
			"meta": {
				"name": "Boyz",
				"keywords": ["INFANTRY", "MOB", "ORKS"]
			}
		},
		"U_GRETCHIN_A": {
			"owner": 2,
			"status": UnitStatus.UNDEPLOYED,
			"models": [
				{"id": "m1", "wounds": 1, "base_mm": 25, "pos": null},
				{"id": "m2", "wounds": 1, "base_mm": 25, "pos": null},
				{"id": "m3", "wounds": 1, "base_mm": 25, "pos": null},
				{"id": "m4", "wounds": 1, "base_mm": 25, "pos": null},
				{"id": "m5", "wounds": 1, "base_mm": 25, "pos": null}
			],
			"meta": {
				"name": "Gretchin",
				"keywords": ["INFANTRY", "GROTS", "ORKS"]
			}
		}
	}

func _get_dawn_of_war_zone_1() -> PackedVector2Array:
	var board_width = 1760  # 44 inches * 40 px/inch
	var board_height = 2400 # 60 inches * 40 px/inch
	var zone_depth = 480    # 12 inches * 40 px/inch
	
	return PackedVector2Array([
		Vector2(0, 0),
		Vector2(board_width, 0),
		Vector2(board_width, zone_depth),
		Vector2(0, zone_depth)
	])

func _get_dawn_of_war_zone_2() -> PackedVector2Array:
	var board_width = 1760
	var board_height = 2400
	var zone_depth = 480
	
	return PackedVector2Array([
		Vector2(0, board_height - zone_depth),
		Vector2(board_width, board_height - zone_depth),
		Vector2(board_width, board_height),
		Vector2(0, board_height)
	])

func get_model_count(unit_id: String) -> int:
	if not units.has(unit_id):
		return 0
	return units[unit_id]["models"].size()

func get_unit_owner(unit_id: String) -> int:
	if not units.has(unit_id):
		return 0
	return units[unit_id]["owner"]

func get_unit_status(unit_id: String) -> UnitStatus:
	if not units.has(unit_id):
		return UnitStatus.UNDEPLOYED
	return units[unit_id]["status"]

func set_unit_status(unit_id: String, status: UnitStatus) -> void:
	if units.has(unit_id):
		units[unit_id]["status"] = status

func get_undeployed_units_for_player(player: int) -> Array:
	var result = []
	for unit_id in units:
		if units[unit_id]["owner"] == player and units[unit_id]["status"] == UnitStatus.UNDEPLOYED:
			result.append(unit_id)
	return result

func all_units_deployed() -> bool:
	for unit_id in units:
		if units[unit_id]["status"] != UnitStatus.DEPLOYED:
			return false
	return true

func has_undeployed_units(player: int) -> bool:
	for unit_id in units:
		if units[unit_id]["owner"] == player and units[unit_id]["status"] == UnitStatus.UNDEPLOYED:
			return true
	return false

func get_deployment_zone_for_player(player: int) -> PackedVector2Array:
	for zone in deployment_zones:
		if zone["player"] == player:
			return zone["poly"]
	return PackedVector2Array()

func model_id(unit_id: String, model_index: int) -> String:
	if not units.has(unit_id):
		return ""
	var models = units[unit_id]["models"]
	if model_index >= 0 and model_index < models.size():
		return models[model_index]["id"]
	return ""

func set_model_position(unit_id: String, model_id: String, pos: Vector2) -> void:
	if not units.has(unit_id):
		return
	for model in units[unit_id]["models"]:
		if model["id"] == model_id:
			model["pos"] = pos
			break

func get_model_base_mm(unit_id: String, model_index: int) -> int:
	if not units.has(unit_id):
		return 32
	var models = units[unit_id]["models"]
	if model_index >= 0 and model_index < models.size():
		return models[model_index]["base_mm"]
	return 32
