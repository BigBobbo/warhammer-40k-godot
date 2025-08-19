extends Node
class_name GameStateData

# Modular Game State for Warhammer 40k
# This class represents the complete game state that can be serialized and passed between phases

enum Phase { DEPLOYMENT, MOVEMENT, SHOOTING, CHARGE, FIGHT, MORALE }
enum UnitStatus { UNDEPLOYED, DEPLOYING, DEPLOYED, MOVED, SHOT, CHARGED, FOUGHT }

# The complete game state as a dictionary
var state: Dictionary = {}

func _ready() -> void:
	initialize_default_state()

func initialize_default_state() -> void:
	state = {
		"meta": {
			"game_id": generate_game_id(),
			"turn_number": 1,
			"active_player": 1,  # Player 1 should start
			"phase": Phase.DEPLOYMENT,
			"created_at": Time.get_unix_time_from_system(),
			"version": "1.0.0"
		},
		"board": {
			"size": {"width": 44, "height": 60},  # inches
			"deployment_zones": [
				{
					"player": 1,
					"poly": _get_dawn_of_war_zone_1_coords()
				},
				{
					"player": 2,
					"poly": _get_dawn_of_war_zone_2_coords()
				}
			],
			"objectives": [],
			"terrain": []
		},
		"units": {
			"U_INTERCESSORS_A": {
				"id": "U_INTERCESSORS_A",
				"squad_id": "U_INTERCESSORS_A",
				"owner": 1,
				"status": UnitStatus.UNDEPLOYED,
				"meta": {
					"name": "Intercessor Squad",
					"keywords": ["INFANTRY", "PRIMARIS", "IMPERIUM", "ADEPTUS ASTARTES"],
					"stats": {"move": 6, "toughness": 4, "save": 3}
				},
				"models": [
					{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m2", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m3", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m4", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m5", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []}
				]
			},
			"U_TACTICAL_A": {
				"id": "U_TACTICAL_A",
				"squad_id": "U_TACTICAL_A",
				"owner": 1,
				"status": UnitStatus.UNDEPLOYED,
				"meta": {
					"name": "Tactical Squad",
					"keywords": ["INFANTRY", "IMPERIUM", "ADEPTUS ASTARTES"],
					"stats": {"move": 6, "toughness": 4, "save": 3}
				},
				"models": [
					{"id": "m1", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m2", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m3", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m4", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m5", "wounds": 2, "current_wounds": 2, "base_mm": 32, "position": null, "alive": true, "status_effects": []}
				]
			},
			"U_BOYZ_A": {
				"id": "U_BOYZ_A",
				"squad_id": "U_BOYZ_A",
				"owner": 2,
				"status": UnitStatus.UNDEPLOYED,
				"meta": {
					"name": "Boyz",
					"keywords": ["INFANTRY", "MOB", "ORKS"],
					"stats": {"move": 6, "toughness": 5, "save": 6}
				},
				"models": [
					{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m2", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m3", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m4", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m5", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m6", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m7", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m8", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m9", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []},
					{"id": "m10", "wounds": 1, "current_wounds": 1, "base_mm": 32, "position": null, "alive": true, "status_effects": []}
				]
			},
			"U_GRETCHIN_A": {
				"id": "U_GRETCHIN_A",
				"squad_id": "U_GRETCHIN_A",
				"owner": 2,
				"status": UnitStatus.UNDEPLOYED,
				"meta": {
					"name": "Gretchin",
					"keywords": ["INFANTRY", "GROTS", "ORKS"],
					"stats": {"move": 5, "toughness": 3, "save": 7}
				},
				"models": [
					{"id": "m1", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": null, "alive": true, "status_effects": []},
					{"id": "m2", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": null, "alive": true, "status_effects": []},
					{"id": "m3", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": null, "alive": true, "status_effects": []},
					{"id": "m4", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": null, "alive": true, "status_effects": []},
					{"id": "m5", "wounds": 1, "current_wounds": 1, "base_mm": 25, "position": null, "alive": true, "status_effects": []}
				]
			}
		},
		"players": {
			"1": {"cp": 3, "vp": 0},
			"2": {"cp": 3, "vp": 0}
		},
		"phase_log": [],
		"history": []
	}

func generate_game_id() -> String:
	var uuid = "%08x-%04x-%04x-%04x-%012x" % [
		randi(),
		randi() & 0xFFFF,
		randi() & 0xFFFF | 0x4000,
		randi() & 0x3FFF | 0x8000,
		randi() << 32 | randi()
	]
	return uuid

func _get_dawn_of_war_zone_1_coords() -> Array:
	return [
		{"x": 0, "y": 0},
		{"x": 44, "y": 0},
		{"x": 44, "y": 12},
		{"x": 0, "y": 12}
	]

func _get_dawn_of_war_zone_2_coords() -> Array:
	return [
		{"x": 0, "y": 48},
		{"x": 44, "y": 48},
		{"x": 44, "y": 60},
		{"x": 0, "y": 60}
	]

# State Access Methods
func get_current_phase() -> Phase:
	return state["meta"]["phase"]

func get_active_player() -> int:
	return state["meta"]["active_player"]

func get_turn_number() -> int:
	return state["meta"]["turn_number"]

func get_units_for_player(player: int) -> Dictionary:
	var player_units = {}
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["owner"] == player:
			player_units[unit_id] = unit
	return player_units

func get_unit(unit_id: String) -> Dictionary:
	return state["units"].get(unit_id, {})

func get_undeployed_units_for_player(player: int) -> Array:
	var undeployed = []
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["owner"] == player and unit["status"] == UnitStatus.UNDEPLOYED:
			undeployed.append(unit_id)
	return undeployed

func has_undeployed_units(player: int) -> bool:
	return get_undeployed_units_for_player(player).size() > 0

func all_units_deployed() -> bool:
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		if unit["status"] == UnitStatus.UNDEPLOYED:
			return false
	return true

func get_deployment_zone_for_player(player: int) -> Dictionary:
	for zone in state["board"]["deployment_zones"]:
		if zone["player"] == player:
			return zone
	return {}

# State Modification Methods
func set_phase(new_phase: Phase) -> void:
	state["meta"]["phase"] = new_phase

func set_active_player(player: int) -> void:
	state["meta"]["active_player"] = player

func advance_turn() -> void:
	state["meta"]["turn_number"] += 1

func add_action_to_phase_log(action: Dictionary) -> void:
	state["phase_log"].append(action)

func commit_phase_log_to_history() -> void:
	if state["phase_log"].size() > 0:
		var phase_entry = {
			"turn": state["meta"]["turn_number"],
			"phase": state["meta"]["phase"],
			"actions": state["phase_log"].duplicate()
		}
		state["history"].append(phase_entry)
		state["phase_log"].clear()

# Create a deep copy of the current state
func create_snapshot() -> Dictionary:
	return _deep_copy_dict(state)

func _deep_copy_dict(dict: Dictionary) -> Dictionary:
	var copy = {}
	for key in dict:
		var value = dict[key]
		if value is Dictionary:
			copy[key] = _deep_copy_dict(value)
		elif value is Array:
			copy[key] = _deep_copy_array(value)
		else:
			copy[key] = value
	return copy

func _deep_copy_array(array: Array) -> Array:
	var copy = []
	for item in array:
		if item is Dictionary:
			copy.append(_deep_copy_dict(item))
		elif item is Array:
			copy.append(_deep_copy_array(item))
		else:
			copy.append(item)
	return copy

# Load state from a snapshot
func load_from_snapshot(snapshot: Dictionary) -> void:
	state = _deep_copy_dict(snapshot)

# Validation
func validate_state() -> Dictionary:
	var errors = []
	
	# Check required keys
	var required_keys = ["meta", "board", "units", "players", "phase_log", "history"]
	for key in required_keys:
		if not state.has(key):
			errors.append("Missing required key: " + key)
	
	# Check meta structure
	if state.has("meta"):
		var meta_keys = ["game_id", "turn_number", "active_player", "phase"]
		for key in meta_keys:
			if not state["meta"].has(key):
				errors.append("Missing meta key: " + key)
	
	var is_valid = errors.size() == 0
	return {
		"valid": is_valid,
		"errors": errors
	}
