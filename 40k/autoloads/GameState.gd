extends Node
class_name GameStateData

# Modular Game State for Warhammer 40k
# This class represents the complete game state that can be serialized and passed between phases

enum Phase { DEPLOYMENT, COMMAND, MOVEMENT, SHOOTING, CHARGE, FIGHT, SCORING, MORALE }
enum UnitStatus { UNDEPLOYED, DEPLOYING, DEPLOYED, MOVED, SHOT, CHARGED, FOUGHT }

# The complete game state as a dictionary
var state: Dictionary = {}

func _ready() -> void:
	initialize_default_state()

func initialize_default_state() -> void:
	# Initialize base state structure
	state = {
		"meta": {
			"game_id": generate_game_id(),
			"turn_number": 1,
			"battle_round": 1,  # Track battle rounds (1-5 in standard 40K)
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
			"terrain": [],
			"terrain_features": []  # Added for terrain system
		},
		"units": {},  # Start empty, will be populated by army loading
		"players": {
			"1": {"cp": 3, "vp": 0},
			"2": {"cp": 3, "vp": 0}
		},
		"factions": {},  # New field for faction data
		"phase_log": [],
		"history": []
	}
	
	# Load default armies
	_load_default_armies()

	# Initialize terrain features from TerrainManager (autoload, not Engine singleton)
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if terrain_manager and terrain_manager.terrain_features.size() > 0:
		state.board["terrain_features"] = terrain_manager.terrain_features.duplicate(true)

func _load_default_armies() -> void:
	print("GameState: Loading default armies...")

	# Check if ArmyListManager autoload is available (it's a scene tree autoload, not an Engine singleton)
	var army_list_manager = get_node_or_null("/root/ArmyListManager")
	if not army_list_manager:
		print("GameState: ArmyListManager not available, falling back to placeholder armies")
		_initialize_placeholder_armies()
		return

	# Try to load test army for Player 1 (Adeptus Custodes)
	var player1_army = army_list_manager.load_army_list("adeptus_custodes", 1)
	if not player1_army.is_empty():
		print("GameState: Loading Adeptus Custodes army for Player 1")
		army_list_manager.apply_army_to_game_state(player1_army, 1)
	else:
		print("GameState: Failed to load Adeptus Custodes, trying Space Marines for Player 1")
		player1_army = army_list_manager.load_army_list("space_marines", 1)
		if not player1_army.is_empty():
			army_list_manager.apply_army_to_game_state(player1_army, 1)
		else:
			print("GameState: Failed to load Space Marines, using placeholder for Player 1")
			_initialize_placeholder_armies_player(1)

	# Load opponent army (Orks for Player 2)
	var player2_army = army_list_manager.load_army_list("orks", 2)
	if not player2_army.is_empty():
		print("GameState: Loading Orks army for Player 2")
		army_list_manager.apply_army_to_game_state(player2_army, 2)
	else:
		print("GameState: Failed to load Orks, using placeholder for Player 2")
		_initialize_placeholder_armies_player(2)
	
	print("GameState: Army loading complete. Total units: ", state.units.size())

func _initialize_placeholder_armies() -> void:
	print("GameState: Initializing placeholder armies for both players")
	_initialize_placeholder_armies_player(1)
	_initialize_placeholder_armies_player(2)

func _initialize_placeholder_armies_player(player: int) -> void:
	print("GameState: Initializing placeholder army for player ", player)
	
	if player == 1:
		# Space Marines placeholder units
		state.units["U_INTERCESSORS_A"] = {
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
		}
		
		state.units["U_TACTICAL_A"] = {
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
		}
		
		state.factions["1"] = {"name": "Space Marines", "points": 0}
		
	else:  # player == 2
		# Ork placeholder units
		state.units["U_BOYZ_A"] = {
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
		}
		
		state.units["U_GRETCHIN_A"] = {
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
		
		state.factions["2"] = {"name": "Orks", "points": 0}

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

func get_faction_name(player: int) -> String:
	if state.has("factions") and state.factions.has(str(player)):
		return state.factions[str(player)].get("name", "Player " + str(player))
	return "Player " + str(player)

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
	var undeployed_list = []
	for unit_id in state["units"]:
		var unit = state["units"][unit_id]
		# Skip units that are embarked (they're deployed when inside a transport)
		if unit.get("embarked_in", null) != null:
			continue
		# Skip units that are attached to a bodyguard (they're deployed with their bodyguard)
		if unit.get("attached_to", null) != null:
			continue
		if unit["status"] == UnitStatus.UNDEPLOYED:
			undeployed_list.append(unit_id + " (player " + str(unit.get("owner", 0)) + ")")

	var all_deployed = undeployed_list.size() == 0
	if not all_deployed:
		print("GameState: ⚠️ all_units_deployed check - Undeployed units: ", undeployed_list)

	return all_deployed

func get_deployment_zone_for_player(player: int) -> Dictionary:
	for zone in state["board"]["deployment_zones"]:
		if zone["player"] == player:
			return zone
	return {}

# Character Attachment Helpers
func is_character(unit_id: String) -> bool:
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false
	var keywords = unit.get("meta", {}).get("keywords", [])
	return "CHARACTER" in keywords

func get_attached_characters(unit_id: String) -> Array:
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return []
	return unit.get("attachment_data", {}).get("attached_characters", [])

func is_attached(unit_id: String) -> bool:
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return false
	return unit.get("attached_to", null) != null

func get_combined_models(unit_id: String) -> Array:
	var unit = get_unit(unit_id)
	if unit.is_empty():
		return []
	var models = unit.get("models", []).duplicate()
	var attached_chars = get_attached_characters(unit_id)
	for char_id in attached_chars:
		var char_unit = get_unit(char_id)
		if not char_unit.is_empty():
			for model in char_unit.get("models", []):
				var combined_model = model.duplicate()
				combined_model["source_unit_id"] = char_id
				combined_model["is_character"] = true
				models.append(combined_model)
	return models

# State Modification Methods
func set_phase(new_phase: Phase) -> void:
	state["meta"]["phase"] = new_phase

func set_active_player(player: int) -> void:
	state["meta"]["active_player"] = player

func advance_turn() -> void:
	state["meta"]["turn_number"] += 1

# Battle Round Management Methods
func get_battle_round() -> int:
	return state["meta"].get("battle_round", 1)

func advance_battle_round() -> void:
	state["meta"]["battle_round"] = get_battle_round() + 1
	print("GameState: Advanced to battle round ", get_battle_round())

func is_game_complete() -> bool:
	return get_battle_round() > 5

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
	# Create base snapshot
	var snapshot = _deep_copy_dict(state)
	
	# Add terrain features from TerrainManager (autoload, not Engine singleton)
	var terrain_manager = get_node_or_null("/root/TerrainManager")
	if terrain_manager and terrain_manager.terrain_features.size() > 0:
		snapshot.board["terrain_features"] = terrain_manager.terrain_features.duplicate(true)

	# Add measuring tape data if persistence is enabled (autoload, not Engine singleton)
	var measuring_tape_manager = get_node_or_null("/root/MeasuringTapeManager")
	if measuring_tape_manager:
		if measuring_tape_manager.save_measurements:
			var tape_data = measuring_tape_manager.get_save_data()
			if not tape_data.is_empty():
				snapshot["measuring_tape"] = tape_data
				print("[GameState] Adding %d measurements to snapshot" % tape_data.size())
			else:
				print("[GameState] No measurements to save (empty data)")
		else:
			print("[GameState] Measuring tape persistence disabled")
	else:
		print("[GameState] MeasuringTapeManager not available")
	
	return snapshot

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
	
	# Load terrain features if present (autoload, not Engine singleton)
	if state.has("board") and state.board.has("terrain_features"):
		var terrain_features = state.board.get("terrain_features", [])
		var terrain_manager = get_node_or_null("/root/TerrainManager")
		if terrain_features.size() > 0 and terrain_manager:
			# Clear and reload terrain
			terrain_manager.terrain_features = terrain_features.duplicate(true)
			terrain_manager.emit_signal("terrain_loaded", terrain_manager.terrain_features)

	# Load measuring tape data if present (autoload, not Engine singleton)
	var measuring_tape_manager = get_node_or_null("/root/MeasuringTapeManager")
	if state.has("measuring_tape") and measuring_tape_manager:
		print("[GameState] Found measuring tape data in save, loading %d measurements" % state["measuring_tape"].size())
		measuring_tape_manager.load_save_data(state["measuring_tape"])
	else:
		if state.has("measuring_tape"):
			print("[GameState] Has measuring_tape but MeasuringTapeManager not available")
		else:
			print("[GameState] No measuring_tape data in save")

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
