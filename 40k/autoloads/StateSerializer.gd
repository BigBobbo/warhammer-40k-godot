extends Node

# StateSerializer - Handles serialization and deserialization of game state
# Provides JSON conversion with versioning, validation, and optimization

signal serialization_completed(data: String)
signal deserialization_completed(state: Dictionary)
signal serialization_error(error: String)

# Save format version history:
# 1.0.0 - Initial save format
# 1.1.0 - Added save format migration system (SAVE-3), formalized formations backfill,
#          ensured all expected top-level sections and meta fields exist
const CURRENT_VERSION = "1.1.0"
const MINIMUM_MIGRATABLE_VERSION = "1.0.0"

# Migration registry: maps source_version -> { "target": next_version, "migrate": Callable }
# Migrations are chained: 1.0.0 -> 1.1.0 -> 1.2.0 -> ... -> CURRENT_VERSION
var _migrations: Dictionary = {}

var compression_enabled: bool = false
var pretty_print: bool = true  # Changed from false

func _ready() -> void:
	_register_migrations()

	# Check if SettingsService has preferences
	if SettingsService and SettingsService.has_method("get_save_pretty_print"):
		pretty_print = SettingsService.get_save_pretty_print()

	print("StateSerializer: Pretty print enabled: ", pretty_print)
	print("StateSerializer: Save format version: %s (min migratable: %s)" % [CURRENT_VERSION, MINIMUM_MIGRATABLE_VERSION])

# ============================================================================
# Save Format Migration System (SAVE-3)
# ============================================================================

func _register_migrations() -> void:
	# Each migration upgrades from one version to the next.
	# To add a new migration: add an entry here and implement the migration function.
	_migrations["1.0.0"] = {
		"target": "1.1.0",
		"migrate": _migrate_1_0_0_to_1_1_0
	}

func migrate_save_data(data: Dictionary) -> Dictionary:
	"""Run all necessary migrations to bring save data up to CURRENT_VERSION.
	Returns the migrated data, or an empty dict if migration fails."""
	if not data.has("_serialization"):
		push_error("StateSerializer: Cannot migrate data without _serialization metadata")
		return {}

	var version = data["_serialization"].get("version", "")
	if version.is_empty():
		push_error("StateSerializer: Cannot migrate data with empty version")
		return {}

	# Already current — no migration needed
	if version == CURRENT_VERSION:
		return data

	# Check if version is too old to migrate
	if _compare_versions(version, MINIMUM_MIGRATABLE_VERSION) < 0:
		push_error("StateSerializer: Save version %s is too old to migrate (minimum: %s)" % [version, MINIMUM_MIGRATABLE_VERSION])
		return {}

	# Check if version is newer than current (future save loaded in older game)
	if _compare_versions(version, CURRENT_VERSION) > 0:
		push_error("StateSerializer: Save version %s is newer than current %s — cannot downgrade" % [version, CURRENT_VERSION])
		return {}

	print("StateSerializer: Migrating save from version %s to %s" % [version, CURRENT_VERSION])
	var migrated_data = data.duplicate(true)

	# Chain migrations until we reach CURRENT_VERSION
	var current_ver = version
	var migration_count = 0
	var max_migrations = 100  # Safety limit to prevent infinite loops

	while current_ver != CURRENT_VERSION and migration_count < max_migrations:
		if not _migrations.has(current_ver):
			push_error("StateSerializer: No migration registered for version %s" % current_ver)
			return {}

		var migration = _migrations[current_ver]
		var target_ver = migration["target"]
		var migrate_func: Callable = migration["migrate"]

		print("StateSerializer: Running migration %s -> %s" % [current_ver, target_ver])
		migrated_data = migrate_func.call(migrated_data)

		if migrated_data.is_empty():
			push_error("StateSerializer: Migration %s -> %s returned empty data" % [current_ver, target_ver])
			return {}

		# Update version in serialization metadata
		migrated_data["_serialization"]["version"] = target_ver
		current_ver = target_ver
		migration_count += 1

	if migration_count >= max_migrations:
		push_error("StateSerializer: Migration chain exceeded safety limit (%d)" % max_migrations)
		return {}

	print("StateSerializer: Migration complete — now at version %s (%d step(s))" % [current_ver, migration_count])
	return migrated_data

func _compare_versions(a: String, b: String) -> int:
	"""Compare two semver strings. Returns -1 if a < b, 0 if a == b, 1 if a > b."""
	var parts_a = a.split(".")
	var parts_b = b.split(".")

	for i in range(max(parts_a.size(), parts_b.size())):
		var num_a = int(parts_a[i]) if i < parts_a.size() else 0
		var num_b = int(parts_b[i]) if i < parts_b.size() else 0
		if num_a < num_b:
			return -1
		elif num_a > num_b:
			return 1

	return 0

func _is_version_migratable(version: String) -> bool:
	"""Check if a version can be migrated to CURRENT_VERSION."""
	if version == CURRENT_VERSION:
		return true
	if _compare_versions(version, MINIMUM_MIGRATABLE_VERSION) < 0:
		return false
	if _compare_versions(version, CURRENT_VERSION) > 0:
		return false
	# Check that a migration path exists
	var current_ver = version
	var steps = 0
	while current_ver != CURRENT_VERSION and steps < 100:
		if not _migrations.has(current_ver):
			return false
		current_ver = _migrations[current_ver]["target"]
		steps += 1
	return current_ver == CURRENT_VERSION

# ============================================================================
# Migration Functions
# ============================================================================

func _migrate_1_0_0_to_1_1_0(data: Dictionary) -> Dictionary:
	"""Migrate from 1.0.0 to 1.1.0.
	Changes:
	- Ensure meta.formations data exists (was previously ad-hoc backfilled in GameState)
	- Ensure meta.formations_declared and confirmation flags exist
	- Ensure meta.battle_round exists
	- Ensure players have bonus_cp_gained_this_round field
	- Ensure factions section exists
	- Ensure unit_visuals section exists
	- Ensure phase_log and history sections exist
	"""
	print("StateSerializer: _migrate_1_0_0_to_1_1_0: Starting migration")

	# Ensure top-level sections exist
	if not data.has("factions"):
		data["factions"] = {}
		print("StateSerializer: _migrate_1_0_0_to_1_1_0: Added missing 'factions' section")

	if not data.has("unit_visuals"):
		data["unit_visuals"] = {}
		print("StateSerializer: _migrate_1_0_0_to_1_1_0: Added missing 'unit_visuals' section")

	if not data.has("phase_log"):
		data["phase_log"] = []
		print("StateSerializer: _migrate_1_0_0_to_1_1_0: Added missing 'phase_log' section")

	if not data.has("history"):
		data["history"] = []
		print("StateSerializer: _migrate_1_0_0_to_1_1_0: Added missing 'history' section")

	# Ensure meta fields exist
	if data.has("meta"):
		var meta = data["meta"]

		# Ensure battle_round exists (older saves may only have turn_number)
		if not meta.has("battle_round"):
			meta["battle_round"] = meta.get("turn_number", 1)
			print("StateSerializer: _migrate_1_0_0_to_1_1_0: Added missing 'battle_round' (set to %d)" % meta["battle_round"])

		# Ensure formations metadata exists for saves past the FORMATIONS phase
		# Phase enum: FORMATIONS=0, DEPLOYMENT=1, ...
		var saved_phase = meta.get("phase", 0)
		if saved_phase > 0:  # Past FORMATIONS phase
			if not meta.has("formations_declared"):
				meta["formations_declared"] = true
				print("StateSerializer: _migrate_1_0_0_to_1_1_0: Inferred formations_declared=true (phase=%d)" % saved_phase)
			if not meta.has("formations_p1_confirmed"):
				meta["formations_p1_confirmed"] = true
				print("StateSerializer: _migrate_1_0_0_to_1_1_0: Inferred formations_p1_confirmed=true")
			if not meta.has("formations_p2_confirmed"):
				meta["formations_p2_confirmed"] = true
				print("StateSerializer: _migrate_1_0_0_to_1_1_0: Inferred formations_p2_confirmed=true")
			if not meta.has("formations"):
				meta["formations"] = {
					"1": {"leader_attachments": {}, "transport_embarkations": {}, "reserves": []},
					"2": {"leader_attachments": {}, "transport_embarkations": {}, "reserves": []}
				}
				print("StateSerializer: _migrate_1_0_0_to_1_1_0: Added default formations data")

		# Ensure version in meta matches
		meta["version"] = "1.1.0"

	# Ensure players have bonus_cp_gained_this_round
	if data.has("players"):
		for player_key in data["players"]:
			var player_data = data["players"][player_key]
			if player_data is Dictionary:
				if not player_data.has("bonus_cp_gained_this_round"):
					player_data["bonus_cp_gained_this_round"] = 0
					print("StateSerializer: _migrate_1_0_0_to_1_1_0: Added bonus_cp_gained_this_round for player %s" % player_key)
				if not player_data.has("primary_vp"):
					player_data["primary_vp"] = 0
				if not player_data.has("secondary_vp"):
					player_data["secondary_vp"] = 0

	print("StateSerializer: _migrate_1_0_0_to_1_1_0: Migration complete")
	return data

# Main serialization methods
func serialize_game_state(state: Dictionary = {}) -> String:
	var target_state = state if not state.is_empty() else GameState.create_snapshot()
	
	var serializable_state = _prepare_for_serialization(target_state)
	if serializable_state.is_empty():
		var error_msg = "Failed to prepare state for serialization"
		emit_signal("serialization_error", error_msg)
		push_error("StateSerializer: " + error_msg)
		return ""
	
	var json_string = ""
	
	if pretty_print:
		json_string = JSON.stringify(serializable_state, "\t")
	else:
		json_string = JSON.stringify(serializable_state)
	
	if json_string.is_empty():
		var error_msg = "Failed to stringify game state"
		emit_signal("serialization_error", error_msg)
		push_error("StateSerializer: " + error_msg)
		return ""
	
	if compression_enabled:
		json_string = _compress_json(json_string)
	
	emit_signal("serialization_completed", json_string)
	return json_string

func deserialize_game_state(json_string: String) -> Dictionary:
	if json_string.is_empty():
		var error_msg = "Empty JSON string provided"
		emit_signal("serialization_error", error_msg)
		push_error("StateSerializer: " + error_msg)
		return {}
	
	var decompressed_string = json_string
	if compression_enabled and _is_compressed(json_string):
		decompressed_string = _decompress_json(json_string)
	
	var json = JSON.new()
	var parse_result = json.parse(decompressed_string)
	
	if parse_result != OK:
		push_error("StateSerializer: JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		emit_signal("serialization_error", "JSON parse error")
		return {}
	
	var parsed_data = json.data
	if not parsed_data is Dictionary:
		push_error("StateSerializer: Parsed data is not a dictionary")
		emit_signal("serialization_error", "Invalid data format")
		return {}
	
	var validation_result = _validate_serialized_data(parsed_data)
	if not validation_result.valid:
		push_error("StateSerializer: Validation failed: " + str(validation_result.errors))
		emit_signal("serialization_error", "Validation failed")
		return {}

	# Log any warnings (e.g., migration needed)
	for warning in validation_result.get("warnings", []):
		print("StateSerializer: WARNING: %s" % warning)

	# Run migrations if save version is older than current
	var save_version = parsed_data.get("_serialization", {}).get("version", CURRENT_VERSION)
	if save_version != CURRENT_VERSION:
		parsed_data = migrate_save_data(parsed_data)
		if parsed_data.is_empty():
			push_error("StateSerializer: Migration failed for version %s" % save_version)
			emit_signal("serialization_error", "Migration failed")
			return {}

	var game_state = _prepare_from_serialization(parsed_data)
	emit_signal("deserialization_completed", game_state)
	return game_state

# Specialized serialization methods
func serialize_partial_state(sections: Array, state: Dictionary = {}) -> String:
	var target_state = state if not state.is_empty() else GameState.create_snapshot()
	var partial_state = {}
	
	# Include metadata always
	partial_state["meta"] = target_state.get("meta", {})
	
	# Include requested sections
	for section in sections:
		if target_state.has(section):
			partial_state[section] = target_state[section]
	
	return serialize_game_state(partial_state)

func serialize_unit_data(unit_ids: Array, state: Dictionary = {}) -> String:
	var target_state = state if not state.is_empty() else GameState.create_snapshot()
	var units_data = {}
	var all_units = target_state.get("units", {})
	
	for unit_id in unit_ids:
		if all_units.has(unit_id):
			units_data[unit_id] = all_units[unit_id]
	
	var partial_state = {
		"meta": target_state.get("meta", {}),
		"units": units_data
	}
	
	return serialize_game_state(partial_state)

func serialize_board_state(state: Dictionary = {}) -> String:
	var sections = ["board", "players"]
	return serialize_partial_state(sections, state)

# File operations
func save_to_file(file_path: String, state: Dictionary = {}) -> bool:
	var json_string = serialize_game_state(state)
	if json_string.is_empty():
		return false
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("StateSerializer: Failed to open file for writing: " + file_path)
		return false
	
	file.store_string(json_string)
	file.close()
	print("StateSerializer: Saved game state to %s" % file_path)
	return true

func load_from_file(file_path: String) -> Dictionary:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("StateSerializer: Failed to open file for reading: " + file_path)
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	return deserialize_game_state(json_string)

# Quick save/load methods
func quick_save(slot: int = 0) -> bool:
	var save_dir = "user://saves/"
	DirAccess.open("user://").make_dir_recursive("saves")
	var file_path = save_dir + "quicksave_%d.json" % slot
	return save_to_file(file_path)

func quick_load(slot: int = 0) -> Dictionary:
	var save_dir = "user://saves/"
	var file_path = save_dir + "quicksave_%d.json" % slot
	return load_from_file(file_path)

func get_save_files() -> Array:
	var save_files = []
	var save_dir = "user://saves/"
	var dir = DirAccess.open(save_dir)
	
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json"):
				save_files.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	
	return save_files

# Preparation methods
func _prepare_for_serialization(state: Dictionary) -> Dictionary:
	var serializable = state.duplicate(true)
	
	# Add serialization metadata
	serializable["_serialization"] = {
		"version": CURRENT_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
		"game_version": CURRENT_VERSION,
		"serializer": "StateSerializer"
	}
	
	# Convert enums to integers for JSON compatibility
	serializable = _convert_enums_to_int(serializable)
	
	# Convert Vector2 and other non-JSON types
	serializable = _convert_complex_types(serializable)
	
	return serializable

func _prepare_from_serialization(data: Dictionary) -> Dictionary:
	var state = data.duplicate(true)
	
	# Remove serialization metadata
	if state.has("_serialization"):
		state.erase("_serialization")
	
	# Convert integers back to enums
	state = _convert_int_to_enums(state)
	
	# Convert back from JSON-compatible types
	state = _restore_complex_types(state)
	
	return state

func _convert_enums_to_int(data) -> Variant:
	if data is Dictionary:
		var converted = {}
		for key in data:
			converted[key] = _convert_enums_to_int(data[key])
		return converted
	elif data is Array:
		var converted = []
		for item in data:
			converted.append(_convert_enums_to_int(item))
		return converted
	else:
		# Check if this is an enum value that needs conversion
		if data is int:
			return data  # Already an int
		return data

func _convert_int_to_enums(data) -> Variant:
	if data is Dictionary:
		var converted = {}
		for key in data:
			converted[key] = _convert_int_to_enums(data[key])
		return converted
	elif data is Array:
		var converted = []
		for item in data:
			converted.append(_convert_int_to_enums(item))
		return converted
	else:
		return data

func _convert_complex_types(data) -> Variant:
	if data is Dictionary:
		var converted = {}
		for key in data:
			converted[key] = _convert_complex_types(data[key])
		return converted
	elif data is Array:
		var converted = []
		for item in data:
			converted.append(_convert_complex_types(item))
		return converted
	elif data is Vector2:
		return {"x": data.x, "y": data.y, "_type": "Vector2"}
	elif data is Vector3:
		return {"x": data.x, "y": data.y, "z": data.z, "_type": "Vector3"}
	elif data is PackedVector2Array:
		var converted_array = []
		for vec in data:
			converted_array.append({"x": vec.x, "y": vec.y, "_type": "Vector2"})
		return {"_type": "PackedVector2Array", "data": converted_array}
	else:
		return data

func _restore_complex_types(data) -> Variant:
	if data is Dictionary:
		# Check if this is a converted complex type
		if data.has("_type"):
			match data._type:
				"Vector2":
					return Vector2(data.x, data.y)
				"Vector3":
					return Vector3(data.x, data.y, data.z)
				"PackedVector2Array":
					var packed = PackedVector2Array()
					for vec_data in data.data:
						packed.append(Vector2(vec_data.x, vec_data.y))
					return packed
				_:
					# Unknown type, return as-is
					return data
		else:
			# Regular dictionary, process recursively
			var converted = {}
			for key in data:
				converted[key] = _restore_complex_types(data[key])
			return converted
	elif data is Array:
		var converted = []
		for item in data:
			converted.append(_restore_complex_types(item))
		return converted
	else:
		return data

# Validation
func _validate_serialized_data(data: Dictionary) -> Dictionary:
	var validation = {
		"valid": true,
		"errors": [],
		"warnings": []
	}

	# Check for serialization metadata
	if not data.has("_serialization"):
		validation.errors.append("Missing serialization metadata")
		validation.valid = false
		return validation

	var serialization_info = data._serialization
	var version = serialization_info.get("version", "")

	# Check version compatibility — allow migratable versions, not just current
	if version.is_empty():
		validation.errors.append("Empty version in serialization metadata")
		validation.valid = false
	elif not _is_version_migratable(version):
		validation.errors.append("Unsupported version: %s (current: %s, min migratable: %s)" % [version, CURRENT_VERSION, MINIMUM_MIGRATABLE_VERSION])
		validation.valid = false
	elif version != CURRENT_VERSION:
		validation.warnings.append("Save version %s will be migrated to %s" % [version, CURRENT_VERSION])

	# Check required game state sections
	var required_sections = ["meta", "board", "units", "players"]
	for section in required_sections:
		if not data.has(section):
			validation.errors.append("Missing required section: " + section)
			validation.valid = false

	# Validate meta section
	if data.has("meta"):
		var meta = data.meta
		var required_meta = ["game_id", "turn_number", "active_player", "phase"]
		for field in required_meta:
			if not meta.has(field):
				validation.errors.append("Missing meta field: " + field)
				validation.valid = false

	return validation

# Compression (basic implementation)
func _compress_json(json_string: String) -> String:
	# Convert string to bytes and compress
	var bytes = json_string.to_utf8_buffer()
	var compressed = bytes.compress(FileAccess.COMPRESSION_GZIP)
	return Marshalls.raw_to_base64(compressed)

func _decompress_json(compressed_string: String) -> String:
	var compressed_data = Marshalls.base64_to_raw(compressed_string)
	var decompressed = compressed_data.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	return decompressed.get_string_from_utf8()

func _is_compressed(data: String) -> bool:
	# Check if string starts with base64 characters and has valid base64 length
	if data.is_empty():
		return false
	# Basic check - base64 strings contain only certain characters
	var base64_pattern = RegEx.new()
	base64_pattern.compile("^[A-Za-z0-9+/]+=*$")
	return base64_pattern.search(data) != null and data.length() % 4 == 0

# Settings and configuration
func set_compression_enabled(enabled: bool) -> void:
	compression_enabled = enabled

func set_pretty_print(enabled: bool) -> void:
	pretty_print = enabled

func get_serialization_info() -> Dictionary:
	return {
		"version": CURRENT_VERSION,
		"minimum_migratable_version": MINIMUM_MIGRATABLE_VERSION,
		"registered_migrations": _migrations.keys(),
		"compression_enabled": compression_enabled,
		"pretty_print": pretty_print
	}

# Utility methods
func calculate_state_size(state: Dictionary = {}) -> Dictionary:
	var target_state = state if not state.is_empty() else GameState.create_snapshot()
	var json_string = serialize_game_state(target_state)
	
	return {
		"uncompressed_bytes": json_string.length(),
		"uncompressed_kb": json_string.length() / 1024.0,
		"compressed_bytes": _compress_json(json_string).length() if compression_enabled else 0,
		"compression_ratio": _compress_json(json_string).length() / float(json_string.length()) if compression_enabled else 1.0
	}

func validate_current_state() -> Dictionary:
	var current_state = GameState.create_snapshot()
	var json_string = serialize_game_state(current_state)
	var deserialized_state = deserialize_game_state(json_string)
	
	return {
		"serialization_successful": not json_string.is_empty(),
		"deserialization_successful": not deserialized_state.is_empty(),
		"round_trip_successful": _compare_states(current_state, deserialized_state)
	}

func _compare_states(state1: Dictionary, state2: Dictionary) -> bool:
	# Simple comparison - in practice you might want more sophisticated comparison
	var json1 = JSON.stringify(state1)
	var json2 = JSON.stringify(state2)
	return json1 == json2

# Debug methods
func print_state_info(state: Dictionary = {}) -> void:
	var target_state = state if not state.is_empty() else GameState.create_snapshot()
	var size_info = calculate_state_size(target_state)
	
	print("=== State Serialization Info ===")
	print("Uncompressed size: %.2f KB" % size_info.uncompressed_kb)
	if compression_enabled:
		print("Compressed size: %.2f KB" % (size_info.compressed_bytes / 1024.0))
		print("Compression ratio: %.2f%%" % (size_info.compression_ratio * 100))
	print("Units count: %d" % target_state.get("units", {}).size())
	print("Phase: %s" % str(target_state.get("meta", {}).get("phase", "unknown")))
	print("Turn: %d" % target_state.get("meta", {}).get("turn_number", 0))
