extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# Autoload for managing army lists and loading configurations

signal army_loaded(army_data: Dictionary)
signal army_load_failed(error: String)

var current_army_data: Dictionary = {}
var available_armies: Array = []

func _ready() -> void:
	scan_available_armies()
	print("ArmyListManager initialized with ", available_armies.size(), " armies: ", available_armies)

func scan_available_armies() -> void:
	available_armies.clear()
	
	# Try to scan armies in res:// directory
	var dir = DirAccess.open("res://armies/")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json"):
				available_armies.append(file_name.get_basename())
			file_name = dir.get_next()
		dir.list_dir_end()
		print("Found armies in res://: ", available_armies)
	else:
		print("Could not open armies directory in res://")
	
	# Also check user:// directory for exported games
	var user_dir = DirAccess.open("user://armies/")
	if user_dir:
		user_dir.list_dir_begin()
		var file_name = user_dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json"):
				var army_name = file_name.get_basename()
				if not army_name in available_armies:
					available_armies.append(army_name)
			file_name = user_dir.get_next()
		user_dir.list_dir_end()
		print("Found additional armies in user://: ", available_armies)

func load_army_list(army_name: String, player: int = 1) -> Dictionary:
	print("Loading army list: ", army_name, " for player ", player)
	
	var file_path = "res://armies/%s.json" % army_name
	
	# Check if file exists in res://
	if not FileAccess.file_exists(file_path):
		# For exported games, try user:// path
		file_path = "user://armies/%s.json" % army_name
		print("Trying user:// path: ", file_path)
		
	if not FileAccess.file_exists(file_path):
		var error_msg = "Army file not found: " + army_name
		print("ERROR: ", error_msg)
		emit_signal("army_load_failed", error_msg)
		return {}
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		var error_msg = "Failed to open army file: " + file_path
		print("ERROR: ", error_msg)
		emit_signal("army_load_failed", error_msg)
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	if json_string.is_empty():
		var error_msg = "Army file is empty: " + army_name
		print("ERROR: ", error_msg)
		emit_signal("army_load_failed", error_msg)
		return {}
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		var error_msg = "JSON parse error in army file %s at line %d: %s" % [army_name, json.get_error_line(), json.get_error_message()]
		print("ERROR: ", error_msg)
		emit_signal("army_load_failed", error_msg)
		return {}
	
	var army_data = json.data
	
	if not army_data is Dictionary:
		var error_msg = "Army data is not a dictionary: " + army_name
		print("ERROR: ", error_msg)
		emit_signal("army_load_failed", error_msg)
		return {}
	
	# Validate required structure
	if not army_data.has("units"):
		var error_msg = "Army data missing 'units' field: " + army_name
		print("ERROR: ", error_msg)
		emit_signal("army_load_failed", error_msg)
		return {}
	
	# Process units to set owner
	if army_data.has("units"):
		for unit_id in army_data.units:
			var unit = army_data.units[unit_id]
			unit["owner"] = player
			
			# Ensure status is properly formatted
			if unit.has("status") and unit.status is String:
				# Convert string status to enum
				match unit.status:
					"UNDEPLOYED":
						unit["status"] = GameStateData.UnitStatus.UNDEPLOYED
					"DEPLOYED":
						unit["status"] = GameStateData.UnitStatus.DEPLOYED
					"MOVED":
						unit["status"] = GameStateData.UnitStatus.MOVED
					"SHOT":
						unit["status"] = GameStateData.UnitStatus.SHOT
					"CHARGED":
						unit["status"] = GameStateData.UnitStatus.CHARGED
					"FOUGHT":
						unit["status"] = GameStateData.UnitStatus.FOUGHT
					_:
						unit["status"] = GameStateData.UnitStatus.UNDEPLOYED
			else:
				unit["status"] = GameStateData.UnitStatus.UNDEPLOYED
			
			# Ensure flags exist
			if not unit.has("flags"):
				unit["flags"] = {}

			# Add transport-related fields
			unit["embarked_in"] = null  # Transport unit ID if embarked
			unit["disembarked_this_phase"] = false  # Track disembark status

			# Check if unit has TRANSPORT keyword and add transport_data
			if unit.has("meta") and unit.meta.has("keywords"):
				if "TRANSPORT" in unit.meta.keywords:
					# Parse transport abilities to extract capacity
					var capacity = 0
					var capacity_keywords = []
					var firing_deck = 0

					if unit.meta.has("abilities"):
						for ability in unit.meta.abilities:
							if ability.has("name") and ability.name == "TRANSPORT":
								# Parse capacity from description
								var desc = ability.get("description", "")
								# Look for pattern like "transport capacity of 22 ORKS INFANTRY"
								var regex = RegEx.new()
								regex.compile("transport capacity of (\\d+)")
								var match = regex.search(desc)
								if match:
									capacity = int(match.get_string(1))

								# Extract keywords (e.g., "22 ORKS INFANTRY models" or "10 INFANTRY models")
								# Pattern: "capacity of <num> <KEYWORD1> <KEYWORD2>... models"
								var keyword_regex = RegEx.new()
								keyword_regex.compile("capacity of \\d+ ([A-Z ]+) models")
								var keyword_match = keyword_regex.search(desc)
								if keyword_match:
									var keywords_str = keyword_match.get_string(1).strip_edges()
									# Split by spaces and filter out common words
									var raw_keywords = keywords_str.split(" ")
									for keyword in raw_keywords:
										keyword = keyword.strip_edges()
										if keyword.length() > 0:
											capacity_keywords.append(keyword)

									DebugLogger.debug("Parsed transport capacity keywords", {
										"unit_id": unit_id,
										"description": desc,
										"keywords": capacity_keywords
									})
							elif ability.has("name") and ability.name == "FIRING DECK":
								var desc = ability.get("description", "")
								var regex = RegEx.new()
								regex.compile("Firing Deck (\\d+)")
								var match = regex.search(desc)
								if match:
									firing_deck = int(match.get_string(1))

					unit["transport_data"] = {
						"capacity": capacity,
						"capacity_keywords": capacity_keywords,
						"embarked_units": [],
						"firing_deck": firing_deck
					}

			print("Processed unit: ", unit_id, " for player ", player)
	
	current_army_data = army_data
	print("Successfully loaded army: ", army_name, " with ", army_data.units.size(), " units")
	emit_signal("army_loaded", army_data)
	return army_data

func apply_army_to_game_state(army_data: Dictionary, player: int) -> void:
	print("Applying army to game state for player: ", player)
	
	if not GameState:
		print("ERROR: GameState not available")
		return
	
	# Get current units
	var all_units = GameState.state.get("units", {})
	
	# Remove existing units for this player
	var units_to_remove = []
	for unit_id in all_units:
		var unit = all_units[unit_id]
		if unit.get("owner", 0) == player:
			units_to_remove.append(unit_id)
	
	print("Removing ", units_to_remove.size(), " existing units for player ", player)
	for unit_id in units_to_remove:
		all_units.erase(unit_id)
	
	# Add new units from army list
	if army_data.has("units"):
		for unit_id in army_data.units:
			var unit = army_data.units[unit_id]
			unit["owner"] = player
			unit["status"] = GameStateData.UnitStatus.UNDEPLOYED
			all_units[unit_id] = unit
			print("Added unit: ", unit_id, " (", unit.get("meta", {}).get("name", unit_id), ")")
	
	# Update GameState
	GameState.state["units"] = all_units
	
	# Store faction data
	if army_data.has("faction"):
		if not GameState.state.has("factions"):
			GameState.state["factions"] = {}
		GameState.state["factions"][str(player)] = army_data.faction
		print("Set faction for player ", player, ": ", army_data.faction.get("name", "Unknown"))
	
	print("Army applied successfully. Total units in game: ", all_units.size())

func get_available_armies() -> Array:
	return available_armies

func get_current_army_data() -> Dictionary:
	return current_army_data

# Validate army structure
func validate_army_structure(army_data: Dictionary) -> Dictionary:
	var result = {"valid": true, "errors": []}
	
	# Check required top-level fields
	if not army_data.has("units"):
		result.valid = false
		result.errors.append("Missing 'units' field")
	
	# Validate units
	if army_data.has("units") and army_data.units is Dictionary:
		for unit_id in army_data.units:
			var unit = army_data.units[unit_id]
			
			if not unit is Dictionary:
				result.valid = false
				result.errors.append("Unit " + unit_id + " is not a dictionary")
				continue
			
			# Check required unit fields
			var required_fields = ["id", "meta", "models"]
			for field in required_fields:
				if not unit.has(field):
					result.valid = false
					result.errors.append("Unit " + unit_id + " missing field: " + field)
			
			# Validate meta section
			if unit.has("meta") and unit.meta is Dictionary:
				if not unit.meta.has("name"):
					result.valid = false
					result.errors.append("Unit " + unit_id + " meta missing 'name' field")
			
			# Validate models
			if unit.has("models") and unit.models is Array:
				if unit.models.size() == 0:
					result.valid = false
					result.errors.append("Unit " + unit_id + " has no models")
			else:
				result.valid = false
				result.errors.append("Unit " + unit_id + " 'models' field is not an array")
	else:
		result.valid = false
		result.errors.append("'units' field is not a dictionary")
	
	return result

# Create a fallback army if loading fails
func create_fallback_army(player: int) -> Dictionary:
	print("Creating fallback army for player ", player)
	
	var army_name = "space_marines" if player == 1 else "orks"
	return {
		"faction": {
			"name": "Fallback Army",
			"points": 0,
			"detachment": "",
			"player_name": "",
			"team_name": ""
		},
		"units": {}
	}
