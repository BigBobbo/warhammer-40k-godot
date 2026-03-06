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

var compression_enabled: bool = true
var pretty_print: bool = true  # Changed from false

# SAVE-17: Only compress saves larger than this threshold (bytes)
# Keeps small saves human-readable for debugging
const COMPRESSION_SIZE_THRESHOLD: int = 50 * 1024  # 50 KB

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
	
	# SAVE-17: Compress only if enabled AND above size threshold
	if compression_enabled and json_string.length() >= COMPRESSION_SIZE_THRESHOLD:
		var original_size = json_string.length()
		json_string = _compress_json(json_string)
		print("StateSerializer: Compressed save %d bytes -> %d bytes (%.1f%%)" % [original_size, json_string.length(), json_string.length() * 100.0 / original_size])
	elif compression_enabled:
		print("StateSerializer: Save size %d bytes below threshold %d, skipping compression" % [json_string.length(), COMPRESSION_SIZE_THRESHOLD])

	emit_signal("serialization_completed", json_string)
	return json_string

func deserialize_game_state(json_string: String) -> Dictionary:
	if json_string.is_empty():
		var error_msg = "Empty JSON string provided"
		emit_signal("serialization_error", error_msg)
		push_error("StateSerializer: " + error_msg)
		return {}
	
	# SAVE-17: Always auto-detect compressed data regardless of compression_enabled setting
	# This ensures old compressed saves can be loaded even if compression is later disabled
	var decompressed_string = json_string
	if _is_compressed(json_string):
		print("StateSerializer: Detected compressed save data, decompressing...")
		decompressed_string = _decompress_json(json_string)
		if decompressed_string.is_empty():
			push_error("StateSerializer: Failed to decompress save data")
			emit_signal("serialization_error", "Decompression failed")
			return {}
	
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

	# SAVE-18: Unit data integrity validation (beyond structural checks)
	var unit_validation = _validate_unit_data(parsed_data)
	if not unit_validation.valid:
		push_error("StateSerializer: SAVE-18 Unit data validation failed: " + str(unit_validation.errors))
		emit_signal("serialization_error", "Unit data validation failed")
		return {}
	for unit_warning in unit_validation.get("warnings", []):
		print("StateSerializer: SAVE-18 WARNING: %s" % unit_warning)

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

# ============================================================================
# SAVE-18: Unit Data Validation on Load
# Validates data integrity beyond structure — catches corruption, out-of-range
# values, and inconsistent references. Returns warnings for fixable issues
# (auto-repaired) and errors for unfixable ones (blocks load).
# ============================================================================

func _validate_unit_data(data: Dictionary) -> Dictionary:
	var validation = {
		"valid": true,
		"errors": [],
		"warnings": [],
		"repairs": []  # Track auto-repairs made
	}

	if not data.has("units") or not data["units"] is Dictionary:
		return validation  # No units to validate (structural check handles this)

	var units = data["units"]
	var all_unit_ids = units.keys()

	for unit_id in units:
		var unit = units[unit_id]
		if not unit is Dictionary:
			validation.errors.append("Unit '%s' is not a Dictionary" % unit_id)
			validation.valid = false
			continue

		var prefix = "Unit '%s'" % unit_id

		# --- Owner validation ---
		var owner = unit.get("owner", -1)
		if not owner is float and not owner is int:
			validation.errors.append("%s: owner is not a number (got %s)" % [prefix, type_string(typeof(owner))])
			validation.valid = false
		elif owner != 1 and owner != 2:
			validation.errors.append("%s: owner must be 1 or 2 (got %s)" % [prefix, str(owner)])
			validation.valid = false

		# --- Status validation ---
		var status = unit.get("status", -1)
		if status is float:
			status = int(status)
		if not status is int:
			validation.errors.append("%s: status is not a number (got %s)" % [prefix, type_string(typeof(status))])
			validation.valid = false
		elif status < 0 or status > 7:
			# UnitStatus enum: UNDEPLOYED=0 through IN_RESERVES=7
			validation.errors.append("%s: status %d out of range [0-7]" % [prefix, status])
			validation.valid = false

		# --- ID consistency ---
		var stored_id = unit.get("id", "")
		if stored_id != "" and stored_id != unit_id:
			validation.warnings.append("%s: id field '%s' doesn't match key '%s' — repairing" % [prefix, stored_id, unit_id])
			unit["id"] = unit_id
			validation.repairs.append("%s: set id to '%s'" % [prefix, unit_id])

		# --- Meta validation ---
		var meta = unit.get("meta", {})
		if not meta is Dictionary:
			validation.errors.append("%s: meta is not a Dictionary" % prefix)
			validation.valid = false
		else:
			# Name
			var unit_name = meta.get("name", "")
			if unit_name == "" or not unit_name is String:
				validation.warnings.append("%s: missing or empty meta.name" % prefix)

			# Keywords
			var keywords = meta.get("keywords", [])
			if not keywords is Array:
				validation.warnings.append("%s: meta.keywords is not an Array — repairing to []" % prefix)
				meta["keywords"] = []
				validation.repairs.append("%s: set keywords to []" % prefix)

			# Stats
			var stats = meta.get("stats", {})
			if stats is Dictionary:
				var stat_fields = ["move", "toughness", "save", "wounds", "leadership", "objective_control"]
				for stat_name in stat_fields:
					if stats.has(stat_name):
						var val = stats[stat_name]
						if val is float:
							val = int(val)
						if val is int and val < 0:
							validation.warnings.append("%s: stat '%s' is negative (%d) — clamping to 0" % [prefix, stat_name, val])
							stats[stat_name] = 0
							validation.repairs.append("%s: clamped %s to 0" % [prefix, stat_name])

			# Weapons
			var weapons = meta.get("weapons", [])
			if weapons is Array:
				for i in range(weapons.size()):
					var weapon = weapons[i]
					if weapon is Dictionary:
						if not weapon.has("name") or weapon["name"] == "":
							validation.warnings.append("%s: weapon[%d] missing name" % [prefix, i])

			# Abilities
			var abilities = meta.get("abilities", [])
			if not abilities is Array:
				validation.warnings.append("%s: meta.abilities is not an Array — repairing to []" % prefix)
				meta["abilities"] = []
				validation.repairs.append("%s: set abilities to []" % prefix)

		# --- Models validation ---
		var models = unit.get("models", [])
		if not models is Array:
			validation.errors.append("%s: models is not an Array" % prefix)
			validation.valid = false
		elif models.size() == 0:
			validation.errors.append("%s: models array is empty" % prefix)
			validation.valid = false
		else:
			var model_ids_seen = {}
			for i in range(models.size()):
				var model = models[i]
				if not model is Dictionary:
					validation.errors.append("%s: model[%d] is not a Dictionary" % [prefix, i])
					validation.valid = false
					continue

				var m_prefix = "%s model[%d]" % [prefix, i]

				# Model ID uniqueness within unit
				var model_id = model.get("id", "")
				if model_id != "":
					if model_ids_seen.has(model_id):
						validation.warnings.append("%s: duplicate model id '%s'" % [m_prefix, model_id])
					model_ids_seen[model_id] = true

				# Wounds validation
				var max_wounds = model.get("wounds", 0)
				var current_wounds = model.get("current_wounds", 0)
				if max_wounds is float:
					max_wounds = int(max_wounds)
				if current_wounds is float:
					current_wounds = int(current_wounds)

				if max_wounds is int and max_wounds < 1:
					validation.warnings.append("%s: wounds < 1 (%d) — setting to 1" % [m_prefix, max_wounds])
					model["wounds"] = 1
					max_wounds = 1
					validation.repairs.append("%s: set wounds to 1" % m_prefix)

				if current_wounds is int and max_wounds is int:
					if current_wounds > max_wounds:
						validation.warnings.append("%s: current_wounds (%d) > wounds (%d) — clamping" % [m_prefix, current_wounds, max_wounds])
						model["current_wounds"] = max_wounds
						validation.repairs.append("%s: clamped current_wounds to %d" % [m_prefix, max_wounds])
					elif current_wounds < 0:
						validation.warnings.append("%s: current_wounds negative (%d) — setting to 0" % [m_prefix, current_wounds])
						model["current_wounds"] = 0
						validation.repairs.append("%s: set current_wounds to 0" % m_prefix)

				# Alive consistency: if current_wounds == 0, model should be dead
				var alive = model.get("alive", true)
				if current_wounds is int and current_wounds <= 0 and alive == true:
					validation.warnings.append("%s: alive=true but current_wounds=%d — setting alive=false" % [m_prefix, current_wounds])
					model["alive"] = false
					validation.repairs.append("%s: set alive=false (0 wounds)" % m_prefix)
				elif current_wounds is int and current_wounds > 0 and alive == false:
					validation.warnings.append("%s: alive=false but current_wounds=%d — setting alive=true" % [m_prefix, current_wounds])
					model["alive"] = true
					validation.repairs.append("%s: set alive=true (%d wounds remaining)" % [m_prefix, current_wounds])

				# Base size validation
				var base_mm = model.get("base_mm", 0)
				if base_mm is float:
					base_mm = int(base_mm)
				if base_mm is int and base_mm <= 0:
					validation.warnings.append("%s: base_mm <= 0 (%s) — setting to 25" % [m_prefix, str(base_mm)])
					model["base_mm"] = 25
					validation.repairs.append("%s: set base_mm to 25" % m_prefix)

				# MA-34: Warn if VEHICLE/MONSTER unit has small base and no base_type
				# Most vehicles use rectangular/oval bases larger than 60mm
				var unit_keywords = meta.get("keywords", []) if meta is Dictionary else []
				var is_vehicle_or_monster = false
				for kw in unit_keywords:
					if str(kw).to_upper() in ["VEHICLE", "MONSTER"]:
						is_vehicle_or_monster = true
						break
				if is_vehicle_or_monster and base_mm is int and base_mm < 60 and not model.has("base_type"):
					validation.warnings.append("%s: VEHICLE/MONSTER unit has small base_mm (%d) and no base_type — may need base_type and base_dimensions" % [m_prefix, base_mm])

				# Status effects
				var status_effects = model.get("status_effects", [])
				if not status_effects is Array:
					validation.warnings.append("%s: status_effects not an Array — repairing to []" % m_prefix)
					model["status_effects"] = []
					validation.repairs.append("%s: set status_effects to []" % m_prefix)

		# --- Cross-reference validation: embarked_in ---
		var embarked_in = unit.get("embarked_in", null)
		if embarked_in != null and embarked_in is String and embarked_in != "":
			if not embarked_in in all_unit_ids:
				validation.warnings.append("%s: embarked_in references non-existent unit '%s' — clearing" % [prefix, embarked_in])
				unit["embarked_in"] = null
				validation.repairs.append("%s: cleared embarked_in (unit not found)" % prefix)

		# --- Cross-reference validation: attached_to ---
		var attached_to = unit.get("attached_to", null)
		if attached_to != null and attached_to is String and attached_to != "":
			if not attached_to in all_unit_ids:
				validation.warnings.append("%s: attached_to references non-existent unit '%s' — clearing" % [prefix, attached_to])
				unit["attached_to"] = null
				validation.repairs.append("%s: cleared attached_to (unit not found)" % prefix)

		# --- Cross-reference validation: attachment_data ---
		var attachment_data = unit.get("attachment_data", {})
		if attachment_data is Dictionary:
			var attached_chars = attachment_data.get("attached_characters", [])
			if attached_chars is Array:
				var valid_chars = []
				for char_id in attached_chars:
					if char_id is String and char_id in all_unit_ids:
						valid_chars.append(char_id)
					else:
						validation.warnings.append("%s: attached_characters references non-existent unit '%s' — removing" % [prefix, str(char_id)])
						validation.repairs.append("%s: removed invalid attached_character '%s'" % [prefix, str(char_id)])
				if valid_chars.size() != attached_chars.size():
					attachment_data["attached_characters"] = valid_chars

		# --- Cross-reference validation: transport embarked_units ---
		var transport_data = unit.get("transport_data", {})
		if transport_data is Dictionary:
			var embarked_units = transport_data.get("embarked_units", [])
			if embarked_units is Array:
				var valid_embarked = []
				for e_id in embarked_units:
					if e_id is String and e_id in all_unit_ids:
						valid_embarked.append(e_id)
					else:
						validation.warnings.append("%s: transport embarked_units references non-existent unit '%s' — removing" % [prefix, str(e_id)])
						validation.repairs.append("%s: removed invalid embarked unit '%s'" % [prefix, str(e_id)])
				if valid_embarked.size() != embarked_units.size():
					transport_data["embarked_units"] = valid_embarked

	# --- Player data validation ---
	if data.has("players") and data["players"] is Dictionary:
		for player_key in data["players"]:
			var player = data["players"][player_key]
			if not player is Dictionary:
				continue
			var p_prefix = "Player '%s'" % player_key
			# CP should be non-negative
			var cp = player.get("cp", 0)
			if cp is float:
				cp = int(cp)
			if cp is int and cp < 0:
				validation.warnings.append("%s: CP is negative (%d) — setting to 0" % [p_prefix, cp])
				player["cp"] = 0
				validation.repairs.append("%s: set CP to 0" % p_prefix)
			# VP should be non-negative
			for vp_key in ["vp", "primary_vp", "secondary_vp"]:
				var vp = player.get(vp_key, 0)
				if vp is float:
					vp = int(vp)
				if vp is int and vp < 0:
					validation.warnings.append("%s: %s is negative (%d) — setting to 0" % [p_prefix, vp_key, vp])
					player[vp_key] = 0
					validation.repairs.append("%s: set %s to 0" % [p_prefix, vp_key])

	# --- Unit ID uniqueness (verify keys match stored IDs) ---
	# Already checked per-unit above via ID consistency check

	# Log summary
	if validation.repairs.size() > 0:
		print("StateSerializer: SAVE-18 Unit data validation made %d auto-repairs" % validation.repairs.size())
	if validation.warnings.size() > 0:
		print("StateSerializer: SAVE-18 Unit data validation found %d warnings" % validation.warnings.size())
	if validation.errors.size() > 0:
		print("StateSerializer: SAVE-18 Unit data validation found %d errors" % validation.errors.size())

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
