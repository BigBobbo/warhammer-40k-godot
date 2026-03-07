extends Node
const GameStateData = preload("res://autoloads/GameState.gd")

# Autoload for managing army lists and loading configurations

signal army_loaded(army_data: Dictionary)
signal army_load_failed(error: String)
signal cloud_armies_loaded(armies: Array)
signal cloud_army_fetched(army_name: String, army_data: Dictionary)
signal cloud_army_fetch_failed(army_name: String, error: String)

var current_army_data: Dictionary = {}
var available_armies: Array = []
var cloud_army_names: Array = []  # Names of armies available in cloud storage
var cloud_army_cache: Dictionary = {}  # Cache of downloaded cloud army data: army_name -> army_data
var _cloud_armies_connected: bool = false  # Whether CloudStorage signals are connected
var _pending_cloud_fetch: String = ""  # Army name currently being fetched
var _pending_cloud_player: int = 1  # Player for pending cloud fetch

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
					"IN_RESERVES":
						unit["status"] = GameStateData.UnitStatus.IN_RESERVES
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

			# Add character attachment fields
			unit["attached_to"] = null  # Bodyguard unit ID if attached
			unit["attachment_data"] = {"attached_characters": []}  # Character IDs attached to this unit

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

			# Ensure models array has the correct number of entries for this unit
			_ensure_correct_model_count(unit_id, unit)

			# Apply wargear stat bonuses (e.g. Praesidium Shield +1W, Vexilla +1OC, 'Ard Case +2T)
			_apply_wargear_stat_bonuses(unit_id, unit)

			# MA-1: Log model_profiles if present
			if unit.has("meta") and unit.meta.has("model_profiles"):
				print("ArmyListManager: Unit %s (%s) loaded with model_profiles: %s" % [unit_id, unit.meta.get("name", "?"), str(unit.meta.model_profiles.keys())])

			# MA-2: Log model_type assignments if model_profiles present
			if unit.has("meta") and unit.meta.has("model_profiles") and unit.has("models") and unit.models is Array:
				var type_counts := {}
				var untyped_count := 0
				for model in unit.models:
					var mt = model.get("model_type", null)
					if mt != null and mt is String and not mt.is_empty():
						type_counts[mt] = type_counts.get(mt, 0) + 1
					else:
						untyped_count += 1
				var summary_parts := []
				for key in type_counts:
					summary_parts.append("%dx %s" % [type_counts[key], key])
				if untyped_count > 0:
					summary_parts.append("%dx (no model_type)" % untyped_count)
				print("ArmyListManager: MA-2 Unit %s (%s) model_type breakdown: %s" % [unit_id, unit.meta.get("name", "?"), ", ".join(summary_parts)])

			print("Processed unit: ", unit_id, " for player ", player)

	# Validate army construction points and detachment
	var construction_result = validate_army_construction_points(army_data)
	if not construction_result.valid:
		for err in construction_result.errors:
			print("ARMY CONSTRUCTION ERROR: ", err)
	# Warnings are logged inside validate_army_construction_points but don't block loading

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

	# Load faction stratagems for this player
	var stratagem_manager = get_node_or_null("/root/StratagemManager")
	if stratagem_manager:
		stratagem_manager.load_faction_stratagems_for_player(player)

	print("Army applied successfully. Total units in game: ", all_units.size())

func get_available_armies() -> Array:
	return available_armies

func get_current_army_data() -> Dictionary:
	return current_army_data

# ============================================================================
# Cloud Army Support
# ============================================================================

func is_cloud_army(army_name: String) -> bool:
	return army_name in cloud_army_names and army_name not in available_armies

func get_all_armies_with_source() -> Array:
	## Returns array of { "id": name, "source": "local" or "cloud" } for all available armies
	var result: Array = []
	for name in available_armies:
		result.append({"id": name, "source": "local"})
	for name in cloud_army_names:
		if name not in available_armies:
			result.append({"id": name, "source": "cloud"})
	return result

func load_cloud_armies() -> void:
	## Fetch available cloud armies from the server via CloudStorage.
	## Results arrive asynchronously via the cloud_armies_loaded signal.
	if not CloudStorage:
		print("ArmyListManager: CloudStorage not available, skipping cloud army fetch")
		return

	if not _cloud_armies_connected:
		CloudStorage.armies_list_received.connect(_on_cloud_armies_list_received)
		CloudStorage.army_downloaded.connect(_on_cloud_army_downloaded)
		CloudStorage.request_failed.connect(_on_cloud_request_failed)
		_cloud_armies_connected = true

	print("ArmyListManager: Requesting cloud army list from server")
	CloudStorage.list_armies()

func fetch_cloud_army(army_name: String, player: int = 1) -> void:
	## Download a specific cloud army. Result arrives via cloud_army_fetched signal.
	## If the army is already cached, emits immediately.
	if army_name in cloud_army_cache:
		print("ArmyListManager: Cloud army '%s' found in cache" % army_name)
		var army_data = _process_army_data(cloud_army_cache[army_name].duplicate(true), player)
		cloud_army_fetched.emit(army_name, army_data)
		return

	if not CloudStorage:
		print("ArmyListManager: CloudStorage not available, cannot fetch cloud army")
		cloud_army_fetch_failed.emit(army_name, "CloudStorage not available")
		return

	if not _cloud_armies_connected:
		CloudStorage.armies_list_received.connect(_on_cloud_armies_list_received)
		CloudStorage.army_downloaded.connect(_on_cloud_army_downloaded)
		CloudStorage.request_failed.connect(_on_cloud_request_failed)
		_cloud_armies_connected = true

	_pending_cloud_fetch = army_name
	_pending_cloud_player = player
	print("ArmyListManager: Fetching cloud army '%s' for player %d" % [army_name, player])
	CloudStorage.get_army(army_name)

func load_army_for_game(army_name: String, player: int) -> Dictionary:
	## Load army from local file or cloud cache. Returns empty dict if not found locally
	## and not cached. For cloud armies not yet cached, use fetch_cloud_army() instead.
	# Try local first
	var local_result = load_army_list(army_name, player)
	if not local_result.is_empty():
		return local_result

	# Try cloud cache
	if army_name in cloud_army_cache:
		print("ArmyListManager: Loading cloud army '%s' from cache for player %d" % [army_name, player])
		var army_data = cloud_army_cache[army_name].duplicate(true)
		return _process_army_data(army_data, player)

	print("ArmyListManager: Army '%s' not found locally or in cloud cache" % army_name)
	return {}

func _on_cloud_armies_list_received(armies: Array) -> void:
	cloud_army_names.clear()
	for army_entry in armies:
		var name = ""
		if army_entry is Dictionary:
			name = army_entry.get("army_name", "")
		elif army_entry is String:
			name = army_entry
		if not name.is_empty():
			cloud_army_names.append(name)

	print("ArmyListManager: Received %d cloud armies: %s" % [cloud_army_names.size(), cloud_army_names])
	cloud_armies_loaded.emit(cloud_army_names)

func _on_cloud_army_downloaded(army_name: String, army_data: Dictionary) -> void:
	print("ArmyListManager: Cloud army downloaded: %s" % army_name)
	# Cache the raw army data
	cloud_army_cache[army_name] = army_data

	# If this was a pending fetch, process and emit
	if army_name == _pending_cloud_fetch:
		var processed = _process_army_data(army_data.duplicate(true), _pending_cloud_player)
		_pending_cloud_fetch = ""
		cloud_army_fetched.emit(army_name, processed)

func _on_cloud_request_failed(operation: String, error: String) -> void:
	if operation == "list_armies":
		print("ArmyListManager: Failed to list cloud armies: %s" % error)
		cloud_armies_loaded.emit([])
	elif operation == "get_army" and not _pending_cloud_fetch.is_empty():
		var army_name = _pending_cloud_fetch
		_pending_cloud_fetch = ""
		print("ArmyListManager: Failed to fetch cloud army '%s': %s" % [army_name, error])
		cloud_army_fetch_failed.emit(army_name, error)

func _process_army_data(army_data: Dictionary, player: int) -> Dictionary:
	## Process raw army JSON data the same way load_army_list does (set owner, status, flags, etc.)
	if not army_data.has("units"):
		return army_data

	for unit_id in army_data.units:
		var unit = army_data.units[unit_id]
		unit["owner"] = player

		# Ensure status is properly formatted
		if unit.has("status") and unit.status is String:
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
				"IN_RESERVES":
					unit["status"] = GameStateData.UnitStatus.IN_RESERVES
				_:
					unit["status"] = GameStateData.UnitStatus.UNDEPLOYED
		else:
			unit["status"] = GameStateData.UnitStatus.UNDEPLOYED

		# Ensure flags exist
		if not unit.has("flags"):
			unit["flags"] = {}

		# Add transport-related fields
		unit["embarked_in"] = null
		unit["disembarked_this_phase"] = false

		# Add character attachment fields
		unit["attached_to"] = null
		unit["attachment_data"] = {"attached_characters": []}

		# Check if unit has TRANSPORT keyword and add transport_data
		if unit.has("meta") and unit.meta.has("keywords"):
			if "TRANSPORT" in unit.meta.keywords:
				var capacity = 0
				var capacity_keywords = []
				var firing_deck = 0

				if unit.meta.has("abilities"):
					for ability in unit.meta.abilities:
						if ability.has("name") and ability.name == "TRANSPORT":
							var desc = ability.get("description", "")
							var regex = RegEx.new()
							regex.compile("transport capacity of (\\d+)")
							var match = regex.search(desc)
							if match:
								capacity = int(match.get_string(1))

							var keyword_regex = RegEx.new()
							keyword_regex.compile("capacity of \\d+ ([A-Z ]+) models")
							var keyword_match = keyword_regex.search(desc)
							if keyword_match:
								var keywords_str = keyword_match.get_string(1).strip_edges()
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

		# Ensure models array has the correct number of entries for this unit
		_ensure_correct_model_count(unit_id, unit)

		# Apply wargear stat bonuses (e.g. Praesidium Shield +1W, Vexilla +1OC, 'Ard Case +2T)
		_apply_wargear_stat_bonuses(unit_id, unit)

		# MA-1: Log model_profiles if present
		if unit.has("meta") and unit.meta.has("model_profiles"):
			print("ArmyListManager: Unit %s (%s) loaded with model_profiles: %s" % [unit_id, unit.meta.get("name", "?"), str(unit.meta.model_profiles.keys())])

		# MA-2: Log model_type assignments if model_profiles present
		if unit.has("meta") and unit.meta.has("model_profiles") and unit.has("models") and unit.models is Array:
			var type_counts := {}
			var untyped_count := 0
			for model in unit.models:
				var mt = model.get("model_type", null)
				if mt != null and mt is String and not mt.is_empty():
					type_counts[mt] = type_counts.get(mt, 0) + 1
				else:
					untyped_count += 1
			var summary_parts := []
			for key in type_counts:
				summary_parts.append("%dx %s" % [type_counts[key], key])
			if untyped_count > 0:
				summary_parts.append("%dx (no model_type)" % untyped_count)
			print("ArmyListManager: MA-2 Unit %s (%s) model_type breakdown: %s" % [unit_id, unit.meta.get("name", "?"), ", ".join(summary_parts)])

		print("Processed unit: ", unit_id, " for player ", player)

	# Validate army construction points and detachment (cloud army path)
	var construction_result = validate_army_construction_points(army_data)
	if not construction_result.valid:
		for err in construction_result.errors:
			print("ARMY CONSTRUCTION ERROR (cloud): ", err)

	return army_data

# ============================================================================
# WARGEAR STAT BONUSES
# ============================================================================
# Some wargear items modify unit/model stats permanently (not phase-based).
# These are applied at army load time by modifying meta.stats and model data.
#
# Supported wargear stat bonuses:
#   - Praesidium Shield: +1 Wounds (Custodian Guard)
#   - Vexilla: +1 OC (Custodian Guard)
#   - 'Ard Case: +2 Toughness (Battlewagon) — also removes Firing Deck

# Wargear stat bonus definitions: ability_name -> { stat_changes }
const WARGEAR_STAT_BONUSES: Dictionary = {
	"Praesidium Shield": {
		"stat": "wounds",
		"bonus": 1,
		"apply_to_models": true,
		"description": "+1 Wounds to bearer"
	},
	"Vexilla": {
		"stat": "objective_control",
		"bonus": 1,
		"apply_to_models": false,
		"description": "+1 OC to unit"
	},
	"'Ard Case": {
		"stat": "toughness",
		"bonus": 2,
		"apply_to_models": false,
		"removes_firing_deck": true,
		"description": "+2 Toughness, loses Firing Deck"
	}
}

func _apply_wargear_stat_bonuses(unit_id: String, unit: Dictionary) -> void:
	"""Check unit abilities for wargear stat bonuses and apply them to stats/models."""
	if not unit.has("meta"):
		return

	var meta = unit.meta
	if not meta.has("abilities"):
		return

	for ability in meta.abilities:
		if not ability is Dictionary:
			continue
		var ability_name = ability.get("name", "")
		if ability_name.is_empty():
			continue

		var wargear_def = WARGEAR_STAT_BONUSES.get(ability_name, {})
		if wargear_def.is_empty():
			continue

		# Only apply to Wargear-type abilities
		var ability_type = ability.get("type", "")
		if ability_type != "Wargear":
			continue

		var stat_name = wargear_def.get("stat", "")
		var bonus = wargear_def.get("bonus", 0)
		if stat_name.is_empty() or bonus == 0:
			continue

		# Apply stat bonus to meta.stats
		if meta.has("stats") and meta.stats.has(stat_name):
			var old_value = meta.stats[stat_name]
			meta.stats[stat_name] = old_value + bonus
			print("ArmyListManager: Wargear '%s' on %s (%s): %s %d -> %d (+%d)" % [
				ability_name, meta.get("name", unit_id), unit_id,
				stat_name, old_value, meta.stats[stat_name], bonus
			])

		# If this wargear modifies wounds, also update model wound values
		if wargear_def.get("apply_to_models", false) and stat_name == "wounds":
			if unit.has("models"):
				for model in unit.models:
					var old_wounds = model.get("wounds", 1)
					model["wounds"] = old_wounds + bonus
					# Also update current_wounds if at max (not damaged)
					var old_current = model.get("current_wounds", old_wounds)
					if old_current == old_wounds:
						model["current_wounds"] = old_current + bonus
					print("ArmyListManager: Wargear '%s' updated model %s wounds: %d -> %d" % [
						ability_name, model.get("id", "?"), old_wounds, model["wounds"]
					])

		# Handle 'Ard Case removing Firing Deck
		if wargear_def.get("removes_firing_deck", false):
			if unit.has("transport_data"):
				var old_fd = unit.transport_data.get("firing_deck", 0)
				if old_fd > 0:
					unit.transport_data["firing_deck"] = 0
					print("ArmyListManager: Wargear '%s' on %s: removed Firing Deck %d" % [
						ability_name, meta.get("name", unit_id), old_fd
					])

# ============================================================================
# MODEL COUNT EXPANSION (MA-37)
# ============================================================================
# Ensures the models array matches the expected count from unit_composition.
# When JSON files have fewer models than expected (e.g. 1 model for a 5-model
# squad), this expands the array by cloning existing model data.

func _ensure_correct_model_count(unit_id: String, unit: Dictionary) -> void:
	"""Check if the models array is shorter than expected and expand if needed."""
	if not unit.has("models") or not unit.models is Array:
		return
	if not unit.has("meta") or not unit.meta is Dictionary:
		return

	var expected = _get_expected_model_count(unit.meta)
	if expected <= 0:
		return  # Can't determine expected count

	var current_count = unit.models.size()
	if current_count >= expected:
		return  # Already correct or more than expected

	# Expand the models array by cloning the last existing model
	var template_model = unit.models[current_count - 1]
	var unit_name = unit.meta.get("name", unit_id)

	for i in range(current_count, expected):
		var new_model = template_model.duplicate(true)
		new_model["id"] = "m%d" % (i + 1)
		new_model["position"] = null
		new_model["alive"] = true
		# Reset current_wounds to match max wounds (not damaged)
		new_model["current_wounds"] = new_model.get("wounds", 1)
		unit.models.append(new_model)

	print("ArmyListManager: MA-37 expanded models for %s (%s): %d -> %d models" % [
		unit_name, unit_id, current_count, unit.models.size()
	])

func _get_expected_model_count(meta: Dictionary) -> int:
	"""Determine the expected model count from unit_composition and wargear."""
	var unit_comp = meta.get("unit_composition", [])
	if unit_comp.is_empty():
		return -1

	var wargear: Array = meta.get("wargear", [])

	# Collect composition entries, handling "OR" patterns (take the option matching wargear)
	var options: Array = []  # Array of arrays of {min, max, name} dicts
	var current_option: Array = []

	for comp in unit_comp:
		var desc = str(comp.get("description", ""))
		if desc.strip_edges().to_upper() == "OR":
			if not current_option.is_empty():
				options.append(current_option)
			current_option = []
			continue

		# Handle "N ModelA and M ModelB" pattern (e.g. "1 Runtherd and 10 Gretchin")
		var parts = desc.split(" and ")
		for part in parts:
			part = part.strip_edges()
			var parsed = _parse_composition_entry(part)
			if parsed.min_count > 0:
				current_option.append(parsed)

	if not current_option.is_empty():
		options.append(current_option)

	if options.is_empty():
		return -1

	# For each option, calculate the total using wargear to refine counts
	var best_total = 0
	for option in options:
		var option_total = 0
		for entry in option:
			var wargear_count = _find_wargear_model_count(wargear, entry.name)
			if wargear_count > 0 and wargear_count >= entry.min_count and wargear_count <= entry.max_count:
				option_total += wargear_count
			else:
				option_total += entry.min_count
		if option_total > best_total:
			best_total = option_total

	return best_total if best_total > 0 else -1

func _parse_composition_entry(desc: String) -> Dictionary:
	"""Parse a unit composition entry like '4-8 Burna Boyz' or '1 Warboss'."""
	var regex = RegEx.new()
	regex.compile("^(\\d+)(?:\\s*-\\s*(\\d+))?\\s+(.+)$")
	var result = regex.search(desc)
	if not result:
		return {"min_count": 0, "max_count": 0, "name": ""}

	var min_count = int(result.get_string(1))
	var max_str = result.get_string(2)
	var max_count = int(max_str) if not max_str.is_empty() else min_count
	var name = result.get_string(3).strip_edges()

	# Remove EPIC HERO or similar suffixes
	var hero_idx = name.find(" – ")
	if hero_idx > 0:
		name = name.substr(0, hero_idx).strip_edges()

	return {"min_count": min_count, "max_count": max_count, "name": name}

func _find_wargear_model_count(wargear: Array, model_name: String) -> int:
	"""Try to find the actual model count from wargear 'Nx ModelName' entries."""
	var normalized_name = _normalize_model_name(model_name)
	if normalized_name.is_empty():
		return 0

	var regex = RegEx.new()
	regex.compile("^(\\d+)x\\s+(.+)$")

	for gear_str in wargear:
		var gear = str(gear_str)
		var result = regex.search(gear)
		if not result:
			continue

		var count = int(result.get_string(1))
		var gear_name = result.get_string(2).strip_edges()
		var normalized_gear = _normalize_model_name(gear_name)

		if normalized_gear == normalized_name:
			return count

	return 0

func _normalize_model_name(name: String) -> String:
	"""Normalize a model name for comparison by stripping plural suffixes."""
	name = name.to_lower().strip_edges()
	# Remove trailing 'z' (e.g. "Boyz" -> "Boy")
	if name.ends_with("z") and name.length() > 2:
		name = name.substr(0, name.length() - 1)
	# Remove trailing 's' (e.g. "Spanners" -> "Spanner", "Lootas" -> "Loota")
	elif name.ends_with("s") and name.length() > 2:
		name = name.substr(0, name.length() - 1)
	return name

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

				# MA-1: Validate model_profiles if present
				if unit.meta.has("model_profiles"):
					var profiles = unit.meta.model_profiles
					if not profiles is Dictionary:
						result.valid = false
						result.errors.append("Unit " + unit_id + " model_profiles is not a dictionary")
					else:
						var weapon_names = []
						if unit.meta.has("weapons") and unit.meta.weapons is Array:
							for w in unit.meta.weapons:
								if w is Dictionary and w.has("name"):
									weapon_names.append(w.name)
						for profile_key in profiles:
							var profile = profiles[profile_key]
							if not profile is Dictionary:
								result.valid = false
								result.errors.append("Unit %s model_profiles.%s is not a dictionary" % [unit_id, profile_key])
								continue
							# Validate required fields
							if not profile.has("label") or not profile.label is String:
								result.errors.append("Unit %s model_profiles.%s missing or invalid 'label'" % [unit_id, profile_key])
							if not profile.has("weapons") or not profile.weapons is Array:
								result.errors.append("Unit %s model_profiles.%s missing or invalid 'weapons'" % [unit_id, profile_key])
							else:
								# Validate weapon references
								for weapon_ref in profile.weapons:
									if weapon_ref not in weapon_names:
										result.errors.append("Unit %s model_profiles.%s references unknown weapon '%s'" % [unit_id, profile_key, weapon_ref])
							# Ensure stats_override defaults to empty dict
							if not profile.has("stats_override"):
								profile["stats_override"] = {}
							# Ensure transport_slots defaults to 1
							if not profile.has("transport_slots"):
								profile["transport_slots"] = 1
						print("ArmyListManager: Unit %s (%s) has model_profiles: %s" % [unit_id, unit.meta.get("name", "?"), str(profiles.keys())])
			
			# Validate models
			if unit.has("models") and unit.models is Array:
				if unit.models.size() == 0:
					result.valid = false
					result.errors.append("Unit " + unit_id + " has no models")
				else:
					# MA-2: Validate model_type on each model if model_profiles exists
					var has_profiles = unit.has("meta") and unit.meta is Dictionary and unit.meta.has("model_profiles") and unit.meta.model_profiles is Dictionary
					if has_profiles:
						var profile_keys = unit.meta.model_profiles.keys()
						for model in unit.models:
							if model is Dictionary and model.has("model_type") and model.model_type != null:
								var mt = str(model.model_type)
								if mt not in profile_keys:
									result.errors.append("Unit %s model %s has model_type '%s' which is not in model_profiles keys: %s" % [unit_id, model.get("id", "?"), mt, str(profile_keys)])
								else:
									# Valid model_type reference
									pass
							# Models without model_type use legacy behavior — no error needed
					# MA-34: Warn if VEHICLE/MONSTER has models with small bases and no base_type
					var kw_list = unit.get("meta", {}).get("keywords", [])
					var has_vehicle_kw = false
					for kw in kw_list:
						if str(kw).to_upper() in ["VEHICLE", "MONSTER"]:
							has_vehicle_kw = true
							break
					if has_vehicle_kw:
						for model in unit.models:
							var bm = model.get("base_mm", 0)
							if bm is float:
								bm = int(bm)
							if bm < 60 and not model.has("base_type"):
								print("WARNING: Unit %s (%s) is VEHICLE/MONSTER but model %s has small base_mm=%d and no base_type — likely needs base_type and base_dimensions" % [unit_id, unit.get("meta", {}).get("name", "?"), model.get("id", "?"), bm])
			else:
				result.valid = false
				result.errors.append("Unit " + unit_id + " 'models' field is not an array")
	else:
		result.valid = false
		result.errors.append("'units' field is not a dictionary")
	
	return result

# ============================================================================
# ARMY CONSTRUCTION POINTS VALIDATION (GEN-10)
# ============================================================================
# Validates army composition against 10th Edition army construction rules:
# - Total unit points must not exceed the declared army points limit
# - Each unit must have a points cost defined
# - A valid detachment must be declared
# - Faction data must include required fields

# Standard game sizes per 10th Edition Muster Rules
const STANDARD_GAME_SIZES: Array = [500, 1000, 1500, 2000, 3000]

func validate_army_construction_points(army_data: Dictionary) -> Dictionary:
	"""Validate army construction points and detachment rules.
	Returns a dictionary with 'valid' (bool), 'errors' (Array), and 'warnings' (Array).
	Errors are hard failures (missing data). Warnings are rule violations that don't block loading."""
	var result = {"valid": true, "errors": [], "warnings": []}

	# --- Faction field validation ---
	if not army_data.has("faction") or not army_data.faction is Dictionary:
		result.valid = false
		result.errors.append("Missing or invalid 'faction' field — army construction cannot be validated")
		return result

	var faction = army_data.faction
	var faction_name = faction.get("name", "Unknown")

	# Check faction has a declared points limit
	# JSON parser returns floats, so cast to int for comparison
	var declared_points: int = int(faction.get("points", -1))
	if declared_points < 0:
		result.valid = false
		result.errors.append("Faction '%s' has no 'points' field — army points limit is required" % faction_name)

	# --- Detachment validation ---
	var detachment = faction.get("detachment", "")
	if detachment.is_empty():
		result.warnings.append("No detachment declared for faction '%s' — detachment rules will not apply" % faction_name)
	else:
		# Check if detachment is recognized by FactionAbilityManager
		var faction_ability_manager = get_node_or_null("/root/FactionAbilityManager")
		if faction_ability_manager and faction_ability_manager.has_method("is_valid_detachment"):
			if not faction_ability_manager.is_valid_detachment(detachment):
				result.warnings.append("Detachment '%s' is not recognized — detachment abilities will not activate" % detachment)
		else:
			print("ArmyListManager: FactionAbilityManager not available for detachment validation")

	# --- Unit points validation ---
	if not army_data.has("units") or not army_data.units is Dictionary:
		# Structure validation handles this — don't duplicate
		return result

	var total_unit_points: int = 0
	var units_missing_points: Array = []
	var unit_count: int = 0

	for unit_id in army_data.units:
		var unit = army_data.units[unit_id]
		if not unit is Dictionary:
			continue

		unit_count += 1
		var meta = unit.get("meta", {})
		var unit_name = meta.get("name", unit_id)
		var unit_points: int = int(meta.get("points", -1))

		if unit_points < 0:
			units_missing_points.append(unit_name + " (" + unit_id + ")")
		elif unit_points == 0:
			result.warnings.append("Unit '%s' (%s) has 0 points cost" % [unit_name, unit_id])
		else:
			total_unit_points += unit_points

	# Report units missing points
	if units_missing_points.size() > 0:
		result.warnings.append("Units missing points cost: %s" % ", ".join(units_missing_points))

	# --- Points limit comparison ---
	if declared_points >= 0 and units_missing_points.size() == 0:
		if total_unit_points > declared_points:
			result.warnings.append(
				"Army exceeds declared points limit: %d / %d pts (+%d over)" % [
					total_unit_points, declared_points, total_unit_points - declared_points
				]
			)

		# Check if declared points matches a standard game size
		if declared_points > 0 and declared_points not in STANDARD_GAME_SIZES:
			result.warnings.append(
				"Declared points limit (%d) is not a standard game size (%s)" % [
					declared_points, str(STANDARD_GAME_SIZES)
				]
			)

	# Log the validation summary
	print("ArmyListManager: Army construction validation for '%s':" % faction_name)
	print("  Declared points: %d, Total unit points: %d, Units: %d" % [declared_points, total_unit_points, unit_count])
	if detachment.is_empty():
		print("  Detachment: (none)")
	else:
		print("  Detachment: %s" % detachment)
	if result.errors.size() > 0:
		for err in result.errors:
			print("  ERROR: %s" % err)
	if result.warnings.size() > 0:
		for warn in result.warnings:
			print("  WARNING: %s" % warn)
	if result.errors.size() == 0 and result.warnings.size() == 0:
		print("  All construction checks passed")

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
