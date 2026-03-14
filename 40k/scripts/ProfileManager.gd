class_name ProfileManager
extends RefCounted

# ProfileManager — Utility class for managing per-player AI profiles
# Profiles are stored as JSON files in user://ai_profiles/
# Each profile contains parameters, rules, and metadata for AI behavior customization.

static func get_profiles_dir() -> String:
	return "user://ai_profiles/"

static func ensure_profiles_dir() -> void:
	var dir = DirAccess.open("user://")
	if dir == null:
		push_warning("ProfileManager: Cannot open user:// directory")
		return
	if not dir.dir_exists("ai_profiles"):
		var err = dir.make_dir("ai_profiles")
		if err != OK:
			push_warning("ProfileManager: Failed to create ai_profiles directory: %s" % err)
		else:
			print("ProfileManager: Created ai_profiles directory")

static func list_profiles() -> Array:
	"""Scan user://ai_profiles/ and return array of {name, path, metadata} for each profile."""
	ensure_profiles_dir()
	var profiles: Array = []
	var dir = DirAccess.open(get_profiles_dir())
	if dir == null:
		push_warning("ProfileManager: Cannot open profiles directory")
		return profiles
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var profile_path = get_profiles_dir() + file_name
			var profile_data = load_profile(file_name.get_basename())
			if not profile_data.is_empty():
				profiles.append({
					"name": profile_data.get("profile_name", file_name.get_basename()),
					"path": profile_path,
					"metadata": {
						"description": profile_data.get("description", ""),
						"faction_affinity": profile_data.get("faction_affinity", ""),
						"playstyle": profile_data.get("playstyle", ""),
						"version": profile_data.get("version", 1),
					}
				})
		file_name = dir.get_next()
	dir.list_dir_end()
	print("ProfileManager: Found %d profiles" % profiles.size())
	return profiles

static func load_profile(profile_name: String) -> Dictionary:
	"""Load and parse a profile JSON file. Returns the full dictionary, or empty dict on failure."""
	var path = get_profiles_dir() + profile_name + ".json"
	if not FileAccess.file_exists(path):
		push_warning("ProfileManager: Profile file not found: %s" % path)
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ProfileManager: Failed to open profile file: %s" % path)
		return {}
	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	if parse_result != OK:
		push_warning("ProfileManager: Failed to parse profile JSON '%s': %s" % [path, json.get_error_message()])
		return {}
	var data = json.data
	if not data is Dictionary:
		push_warning("ProfileManager: Profile '%s' root is not a Dictionary" % path)
		return {}
	print("ProfileManager: Loaded profile '%s' from %s" % [data.get("profile_name", profile_name), path])
	return data

static func save_profile(profile_data: Dictionary) -> bool:
	"""Save a profile dictionary to user://ai_profiles/<name>.json. Returns true on success."""
	var profile_name = profile_data.get("profile_name", "")
	if profile_name.is_empty():
		push_warning("ProfileManager: Cannot save profile — missing profile_name")
		return false
	ensure_profiles_dir()
	var path = get_profiles_dir() + profile_name + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("ProfileManager: Failed to open file for writing: %s" % path)
		return false
	var json_string = JSON.stringify(profile_data, "\t")
	file.store_string(json_string)
	file.close()
	print("ProfileManager: Saved profile '%s' to %s" % [profile_name, path])
	return true

static func delete_profile(profile_name: String) -> bool:
	"""Delete a profile file. Returns true on success."""
	var path = get_profiles_dir() + profile_name + ".json"
	if not FileAccess.file_exists(path):
		push_warning("ProfileManager: Cannot delete — profile not found: %s" % path)
		return false
	var dir = DirAccess.open(get_profiles_dir())
	if dir == null:
		push_warning("ProfileManager: Cannot open profiles directory for deletion")
		return false
	var err = dir.remove(profile_name + ".json")
	if err != OK:
		push_warning("ProfileManager: Failed to delete profile '%s': %s" % [profile_name, err])
		return false
	print("ProfileManager: Deleted profile '%s'" % profile_name)
	return true

static func validate_profile(data: Dictionary) -> Dictionary:
	"""Validate a profile dictionary. Returns {valid: bool, errors: Array[String]}."""
	var errors: Array[String] = []
	if data.get("format", "") != "wh40k_ai_profile":
		errors.append("Missing or invalid 'format' field (expected 'wh40k_ai_profile')")
	if not data.has("version") or not (data["version"] is int or data["version"] is float):
		errors.append("Missing or invalid 'version' field (expected integer)")
	if data.get("profile_name", "").is_empty():
		errors.append("Missing or empty 'profile_name'")
	if data.has("parameters") and not data["parameters"] is Dictionary:
		errors.append("'parameters' must be a Dictionary")
	if data.has("rules") and not data["rules"] is Array:
		errors.append("'rules' must be an Array")
	# Validate individual rules
	var rules = data.get("rules", [])
	for i in range(rules.size()):
		var rule = rules[i]
		if not rule is Dictionary:
			errors.append("Rule at index %d is not a Dictionary" % i)
			continue
		if rule.get("id", "").is_empty():
			errors.append("Rule at index %d missing 'id'" % i)
		if not rule.has("conditions") or not rule["conditions"] is Array:
			errors.append("Rule '%s' missing or invalid 'conditions' array" % rule.get("id", str(i)))
		if not rule.has("actions") or not rule["actions"] is Array:
			errors.append("Rule '%s' missing or invalid 'actions' array" % rule.get("id", str(i)))
	return {"valid": errors.is_empty(), "errors": errors}

static func get_profile_parameters(profile_data: Dictionary) -> Dictionary:
	"""Extract the parameters dictionary from a profile."""
	return profile_data.get("parameters", {})

static func get_profile_rules(profile_data: Dictionary) -> Array:
	"""Extract the rules array from a profile."""
	return profile_data.get("rules", [])
