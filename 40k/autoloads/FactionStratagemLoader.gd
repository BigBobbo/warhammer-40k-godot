extends Node
class_name FactionStratagemLoaderData

# FactionStratagemLoader - Parse CSV data and create stratagem definitions
#
# Reads Stratagems.csv, Factions.csv, and Detachments.csv to load faction-specific
# stratagems. Maps faction names (from army JSON) to faction codes (CSV), filters
# by detachment, parses HTML descriptions into structured WHEN/TARGET/EFFECT text,
# and maps effect descriptions to EffectPrimitives effect types where possible.

# ============================================================================
# FACTION NAME → CODE MAPPING
# ============================================================================
# Maps faction names (as used in army JSON files) to CSV faction_id codes.
# This is populated from Factions.csv at load time, plus some manual overrides
# for common variations.

var _faction_name_to_code: Dictionary = {}
var _faction_code_to_name: Dictionary = {}

# ============================================================================
# CSV PARSING
# ============================================================================

static func parse_csv_file(file_path: String, delimiter: String = "|") -> Array:
	"""Parse a pipe-delimited CSV file. Returns array of dictionaries keyed by header names."""
	var results: Array = []

	if not FileAccess.file_exists(file_path):
		print("FactionStratagemLoader: File not found: %s" % file_path)
		return results

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("FactionStratagemLoader: Cannot open file: %s" % file_path)
		return results

	# Read header line
	var header_line = file.get_line()
	# Strip BOM if present
	if header_line.length() > 0 and header_line.unicode_at(0) == 0xFEFF:
		header_line = header_line.substr(1)
	var headers = header_line.split(delimiter)

	# Strip trailing empty header (common with trailing delimiter)
	while headers.size() > 0 and headers[headers.size() - 1].strip_edges() == "":
		headers.remove_at(headers.size() - 1)

	# Read data lines
	while not file.eof_reached():
		var line = file.get_line()
		if line.strip_edges() == "":
			continue

		var values = line.split(delimiter)
		var row: Dictionary = {}
		for i in range(min(headers.size(), values.size())):
			row[headers[i].strip_edges()] = values[i]

		results.append(row)

	file.close()
	return results

# ============================================================================
# FACTION CODE LOADING
# ============================================================================

func load_faction_codes(factions_csv_path: String = "res://data/Factions.csv") -> void:
	"""Load faction name-to-code mappings from Factions.csv."""
	var rows = parse_csv_file(factions_csv_path)
	for row in rows:
		var code = row.get("id", "").strip_edges()
		var name = row.get("name", "").strip_edges()
		if code != "" and name != "":
			_faction_name_to_code[name] = code
			_faction_name_to_code[name.to_lower()] = code
			_faction_code_to_name[code] = name

	# Add common aliases
	_faction_name_to_code["space marines"] = "SM"
	_faction_name_to_code["Space Marines"] = "SM"
	_faction_name_to_code["adeptus custodes"] = "AC"
	_faction_name_to_code["Adeptus Custodes"] = "AC"
	_faction_name_to_code["orks"] = "ORK"
	_faction_name_to_code["Orks"] = "ORK"
	_faction_name_to_code["chaos space marines"] = "CSM"
	_faction_name_to_code["Chaos Space Marines"] = "CSM"
	_faction_name_to_code["aeldari"] = "AE"
	_faction_name_to_code["Aeldari"] = "AE"
	_faction_name_to_code["necrons"] = "NEC"
	_faction_name_to_code["Necrons"] = "NEC"
	_faction_name_to_code["tyranids"] = "TYR"
	_faction_name_to_code["Tyranids"] = "TYR"
	_faction_name_to_code["t'au empire"] = "TAU"
	_faction_name_to_code["T'au Empire"] = "TAU"
	_faction_name_to_code["astra militarum"] = "AM"
	_faction_name_to_code["Astra Militarum"] = "AM"
	_faction_name_to_code["death guard"] = "DG"
	_faction_name_to_code["Death Guard"] = "DG"
	_faction_name_to_code["drukhari"] = "DRU"
	_faction_name_to_code["Drukhari"] = "DRU"

	print("FactionStratagemLoader: Loaded %d faction codes" % _faction_name_to_code.size())

func get_faction_code(faction_name: String) -> String:
	"""Get the CSV faction_id code for a faction name."""
	if _faction_name_to_code.has(faction_name):
		return _faction_name_to_code[faction_name]
	if _faction_name_to_code.has(faction_name.to_lower()):
		return _faction_name_to_code[faction_name.to_lower()]
	# Try partial matching
	for key in _faction_name_to_code:
		if key.to_lower() == faction_name.to_lower():
			return _faction_name_to_code[key]
	print("FactionStratagemLoader: Unknown faction name: '%s'" % faction_name)
	return ""

func get_faction_name(faction_code: String) -> String:
	"""Get the faction name for a CSV faction_id code."""
	return _faction_code_to_name.get(faction_code, "")

# ============================================================================
# STRATAGEM LOADING FROM CSV
# ============================================================================

func load_faction_stratagems(faction_name: String, detachment_name: String, stratagems_csv_path: String = "res://data/Stratagems.csv") -> Array:
	"""
	Load all stratagems for a given faction and detachment from CSV.
	Returns array of stratagem dictionaries in StratagemManager format.
	"""
	var faction_code = get_faction_code(faction_name)
	if faction_code == "":
		print("FactionStratagemLoader: Cannot load stratagems — unknown faction: '%s'" % faction_name)
		return []

	print("FactionStratagemLoader: Loading stratagems for %s (%s), detachment: '%s'" % [faction_name, faction_code, detachment_name])

	var rows = parse_csv_file(stratagems_csv_path)
	var stratagems: Array = []

	for row in rows:
		var row_faction = row.get("faction_id", "").strip_edges()
		if row_faction != faction_code:
			continue

		var row_detachment = row.get("detachment", "").strip_edges()

		# Filter by detachment if specified
		if detachment_name != "" and row_detachment != "" and row_detachment != detachment_name:
			continue

		# Skip Boarding Actions detachment stratagems
		var strat_type = row.get("type", "")
		if "Boarding Actions" in strat_type:
			continue

		var stratagem = _parse_stratagem_row(row, faction_code)
		if not stratagem.is_empty():
			stratagems.append(stratagem)

	print("FactionStratagemLoader: Loaded %d stratagems for %s / %s" % [stratagems.size(), faction_name, detachment_name])
	return stratagems

func load_all_faction_stratagems(faction_name: String, stratagems_csv_path: String = "res://data/Stratagems.csv") -> Dictionary:
	"""
	Load ALL stratagems for a faction (all detachments), grouped by detachment name.
	Returns { "detachment_name": [stratagems...], ... }
	"""
	var faction_code = get_faction_code(faction_name)
	if faction_code == "":
		return {}

	var rows = parse_csv_file(stratagems_csv_path)
	var by_detachment: Dictionary = {}

	for row in rows:
		if row.get("faction_id", "").strip_edges() != faction_code:
			continue
		var strat_type = row.get("type", "")
		if "Boarding Actions" in strat_type:
			continue

		var detachment = row.get("detachment", "").strip_edges()
		if not by_detachment.has(detachment):
			by_detachment[detachment] = []

		var stratagem = _parse_stratagem_row(row, faction_code)
		if not stratagem.is_empty():
			by_detachment[detachment].append(stratagem)

	return by_detachment

# ============================================================================
# STRATAGEM ROW PARSING
# ============================================================================

func _parse_stratagem_row(row: Dictionary, faction_code: String) -> Dictionary:
	"""Parse a CSV row into a stratagem dictionary matching StratagemManager format."""
	var csv_name = row.get("name", "").strip_edges()
	var csv_id = row.get("id", "").strip_edges()
	var csv_type = row.get("type", "").strip_edges()
	var csv_cp = row.get("cp_cost", "1").strip_edges()
	var csv_turn = row.get("turn", "").strip_edges()
	var csv_phase = row.get("phase", "").strip_edges()
	var csv_detachment = row.get("detachment", "").strip_edges()
	var csv_description = row.get("description", "").strip_edges()

	if csv_name == "":
		return {}

	# Generate a unique id
	var strat_id = _generate_stratagem_id(faction_code, csv_detachment, csv_name)

	# Parse timing
	var timing = _parse_timing(csv_turn, csv_phase, csv_description)

	# Parse description into structured components
	var parsed_desc = _parse_description(csv_description)

	# Parse target conditions from the TARGET text
	var target = _parse_target(parsed_desc.get("target_text", ""))

	# Map effects from the EFFECT text
	var effects = _map_effects(parsed_desc.get("effect_text", ""))

	# Parse restrictions from RESTRICTIONS text
	var restrictions = _parse_restrictions(parsed_desc.get("restriction_text", ""), csv_type)

	# Determine if this stratagem is mechanically implemented
	var implemented = effects.size() > 0 and not effects[0].get("type", "").begins_with("custom:")

	return {
		"id": strat_id,
		"csv_id": csv_id,
		"name": csv_name,
		"type": csv_type,
		"cp_cost": int(csv_cp) if csv_cp.is_valid_int() else 1,
		"timing": timing,
		"target": target,
		"effects": effects,
		"restrictions": restrictions,
		"description": parsed_desc.get("effect_text", ""),
		"when_text": parsed_desc.get("when_text", ""),
		"target_text": parsed_desc.get("target_text", ""),
		"effect_text": parsed_desc.get("effect_text", ""),
		"restriction_text": parsed_desc.get("restriction_text", ""),
		"faction_id": faction_code,
		"detachment": csv_detachment,
		"implemented": implemented,
	}

func _generate_stratagem_id(faction_code: String, detachment: String, name: String) -> String:
	"""Generate a unique stratagem ID from faction, detachment, and name."""
	var clean_name = name.to_lower().replace(" ", "_").replace("'", "").replace("-", "_").replace("!", "").replace(",", "")
	var clean_detachment = detachment.to_lower().replace(" ", "_").replace("'", "").replace("-", "_")
	if clean_detachment != "":
		return "faction_%s_%s_%s" % [faction_code.to_lower(), clean_detachment, clean_name]
	return "faction_%s_%s" % [faction_code.to_lower(), clean_name]

# ============================================================================
# TIMING PARSING
# ============================================================================

func _parse_timing(csv_turn: String, csv_phase: String, description: String) -> Dictionary:
	"""Parse turn/phase/trigger from CSV fields and description."""
	var turn = "either"
	match csv_turn.to_lower():
		"your turn":
			turn = "your"
		"opponent's turn":
			turn = "opponent"
		"either player's turn":
			turn = "either"

	var phase = _normalize_phase(csv_phase)
	var trigger = _infer_trigger(description, phase, turn)

	return {
		"turn": turn,
		"phase": phase,
		"trigger": trigger
	}

func _normalize_phase(csv_phase: String) -> String:
	"""Convert CSV phase string to internal phase name."""
	var p = csv_phase.to_lower().strip_edges()
	if "any" in p:
		return "any"
	if "command" in p:
		return "command"
	if "movement" in p:
		if "charge" in p:
			return "movement_or_charge"
		return "movement"
	if "shooting" in p:
		if "fight" in p:
			return "shooting_or_fight"
		return "shooting"
	if "charge" in p:
		return "charge"
	if "fight" in p:
		return "fight"
	return "any"

func _infer_trigger(description: String, phase: String, turn: String) -> String:
	"""Infer the trigger point from the description text."""
	var desc_lower = description.to_lower()

	# Check for specific trigger patterns in WHEN text
	if "just after an enemy unit has selected its targets" in desc_lower:
		return "after_target_selected"
	if "just after an enemy unit has fought" in desc_lower:
		return "after_enemy_fought"
	if "just after an enemy unit ends a charge move" in desc_lower:
		return "after_enemy_charge_move"
	if "just after an enemy unit ends a normal" in desc_lower:
		return "after_enemy_move"
	if "before you take a battle-shock test" in desc_lower:
		return "before_battle_shock_test"
	if "just after you have failed a battle-shock test" in desc_lower:
		return "after_failed_battle_shock_test"
	if "just after you make" in desc_lower or "just after you have made" in desc_lower:
		return "after_roll"
	if "just after a mortal wound" in desc_lower:
		return "after_mortal_wound"
	if "has not been selected to shoot" in desc_lower:
		return "shooter_selected"
	if "has not been selected to fight" in desc_lower:
		return "fighter_selected"
	if "start of" in desc_lower:
		if "fight" in desc_lower:
			return "fight_phase_start"
		if "movement" in desc_lower:
			return "movement_phase_start"
		if "shooting" in desc_lower:
			return "shooting_phase_start"
	if "end of" in desc_lower:
		if "fight" in desc_lower:
			return "fight_phase_end"
		if "command" in desc_lower:
			return "end_of_command_phase"
	if "fell back this phase" in desc_lower:
		return "after_fall_back"
	if "made a charge move this turn" in desc_lower:
		return "after_charge_move"
	if "just after" in desc_lower and "destroyed" in desc_lower:
		return "after_unit_destroyed"

	# Default triggers based on phase/turn
	if phase == "shooting" and turn == "your":
		return "shooting_phase_active"
	if phase == "fight":
		if turn == "opponent":
			return "after_target_selected"
		return "fight_phase_active"
	if phase == "charge" and turn == "your":
		return "charge_phase_active"
	if phase == "command":
		return "command_phase_active"
	if phase == "movement":
		if turn == "opponent":
			return "after_enemy_move"
		return "movement_phase_active"

	return "phase_active"

# ============================================================================
# DESCRIPTION PARSING
# ============================================================================

static func _parse_description(html_description: String) -> Dictionary:
	"""Parse HTML stratagem description into structured WHEN/TARGET/EFFECT/RESTRICTIONS text."""
	var result = {
		"when_text": "",
		"target_text": "",
		"effect_text": "",
		"restriction_text": ""
	}

	if html_description == "":
		return result

	# Strip HTML tags
	var text = _strip_html(html_description)

	# Extract sections
	var when_match = _extract_section(text, "WHEN:", ["TARGET:", "EFFECT:", "RESTRICTIONS:", "RESTRICTION:"])
	var target_match = _extract_section(text, "TARGET:", ["EFFECT:", "RESTRICTIONS:", "RESTRICTION:"])
	var effect_match = _extract_section(text, "EFFECT:", ["RESTRICTIONS:", "RESTRICTION:"])
	var restrict_match = _extract_section(text, "RESTRICTIONS:", [])
	if restrict_match == "":
		restrict_match = _extract_section(text, "RESTRICTION:", [])

	result.when_text = when_match.strip_edges()
	result.target_text = target_match.strip_edges()
	result.effect_text = effect_match.strip_edges()
	result.restriction_text = restrict_match.strip_edges()

	return result

static func _strip_html(html: String) -> String:
	"""Remove HTML tags from a string."""
	var regex = RegEx.new()
	regex.compile("<[^>]+>")
	var result = regex.sub(html, "", true)
	# Clean up extra whitespace
	result = result.replace("\n", " ").replace("\r", " ")
	while "  " in result:
		result = result.replace("  ", " ")
	return result.strip_edges()

static func _extract_section(text: String, start_marker: String, end_markers: Array) -> String:
	"""Extract text between a start marker and the first matching end marker."""
	var start_idx = text.find(start_marker)
	if start_idx == -1:
		return ""

	var content_start = start_idx + start_marker.length()
	var end_idx = text.length()

	for marker in end_markers:
		var idx = text.find(marker, content_start)
		if idx != -1 and idx < end_idx:
			end_idx = idx

	return text.substr(content_start, end_idx - content_start)

# ============================================================================
# TARGET PARSING
# ============================================================================

func _parse_target(target_text: String) -> Dictionary:
	"""Parse TARGET text into structured target conditions."""
	var result = {
		"type": "unit",
		"owner": "friendly",
		"conditions": []
	}

	if target_text == "":
		return result

	var t = target_text.to_lower()

	# Determine owner
	if "enemy" in t:
		result.owner = "enemy"

	# Look for keyword requirements
	var keyword_patterns = [
		["infantry", "keyword:INFANTRY"],
		["vehicle", "keyword:VEHICLE"],
		["monster", "keyword:MONSTER"],
		["character", "keyword:CHARACTER"],
		["battleline", "keyword:BATTLELINE"],
		["terminator", "keyword:TERMINATOR"],
		["mounted", "keyword:MOUNTED"],
	]

	for pattern in keyword_patterns:
		if pattern[0] in t:
			result.conditions.append(pattern[1])

	# Faction keyword requirements
	if "adeptus astartes" in t:
		result.conditions.append("keyword:ADEPTUS ASTARTES")
	if "adeptus custodes" in t:
		result.conditions.append("keyword:ADEPTUS CUSTODES")
	if "orks" in t:
		result.conditions.append("keyword:ORKS")

	# Special conditions
	if "was selected as the target" in t:
		result.conditions.append("is_target_of_attack")
	if "not been selected to shoot" in t:
		result.conditions.append("not_shot")
	if "not been selected to fight" in t:
		result.conditions.append("not_fought")
	if "below half-strength" in t or "below its starting strength" in t:
		result.conditions.append("below_starting_strength")
	if "fell back this phase" in t:
		result.conditions.append("fell_back_this_phase")
	if "made a charge move this turn" in t:
		result.conditions.append("charged_this_turn")
	if "within engagement range" in t:
		result.conditions.append("in_engagement_range")
	if "within range of an objective" in t:
		result.conditions.append("on_objective")

	return result

# ============================================================================
# EFFECT MAPPING
# ============================================================================

func _map_effects(effect_text: String) -> Array:
	"""Map effect description text to EffectPrimitives effect types."""
	if effect_text == "":
		return [{"type": "custom:unknown", "description": "No effect text"}]

	var effects: Array = []
	var t = effect_text.to_lower()

	# --- Stat Modifiers ---

	# Worsen AP
	if "worsen the armour penetration" in t or "worsen the ap" in t:
		var value = _extract_numeric_value(t, "by")
		effects.append({"type": EffectPrimitivesData.WORSEN_AP, "value": value if value > 0 else 1})

	# Improve AP
	if "improve the armour penetration" in t or "improve the ap" in t:
		var value = _extract_numeric_value(t, "by")
		effects.append({"type": EffectPrimitivesData.IMPROVE_AP, "value": value if value > 0 else 1})

	# +1 to hit
	if "add 1 to the hit roll" in t:
		effects.append({"type": EffectPrimitivesData.PLUS_ONE_HIT})

	# -1 to hit
	if "subtract 1 from the hit roll" in t:
		effects.append({"type": EffectPrimitivesData.MINUS_ONE_HIT})

	# +1 to wound
	if "add 1 to the wound roll" in t:
		effects.append({"type": EffectPrimitivesData.PLUS_ONE_WOUND})

	# -1 to wound
	if "subtract 1 from the wound roll" in t:
		effects.append({"type": EffectPrimitivesData.MINUS_ONE_WOUND})

	# +1 to damage / subtract damage
	if "subtract 1 from the damage" in t or "subtract 1 from the damage characteristic" in t:
		effects.append({"type": EffectPrimitivesData.MINUS_DAMAGE, "value": 1})

	# --- Keyword Grants ---

	# Ignores Cover
	if "[ignores cover]" in t:
		effects.append({"type": EffectPrimitivesData.GRANT_IGNORES_COVER})

	# Lethal Hits
	if "[lethal hits]" in t:
		effects.append({"type": EffectPrimitivesData.GRANT_LETHAL_HITS})

	# Sustained Hits
	if "[sustained hits" in t:
		effects.append({"type": EffectPrimitivesData.GRANT_SUSTAINED_HITS})

	# Devastating Wounds
	if "[devastating wounds]" in t:
		effects.append({"type": EffectPrimitivesData.GRANT_DEVASTATING_WOUNDS})

	# Lance
	if "[lance]" in t:
		effects.append({"type": EffectPrimitivesData.GRANT_LANCE})

	# Precision
	if "[precision]" in t:
		var scope = "melee" if "melee" in t else ("ranged" if "ranged" in t else "all")
		effects.append({"type": EffectPrimitivesData.GRANT_PRECISION, "scope": scope})

	# Twin-Linked
	if "[twin-linked]" in t:
		effects.append({"type": EffectPrimitivesData.GRANT_TWIN_LINKED})

	# --- Defensive Effects ---

	# Invulnerable save
	var invuln_regex = RegEx.new()
	invuln_regex.compile("(\\d)\\+\\s*invulnerable save")
	var invuln_match = invuln_regex.search(t)
	if invuln_match:
		effects.append({"type": EffectPrimitivesData.GRANT_INVULN, "value": int(invuln_match.get_string(1))})

	# Benefit of Cover
	if "benefit of cover" in t:
		effects.append({"type": EffectPrimitivesData.GRANT_COVER})

	# Stealth
	if "stealth" in t and "ability" in t:
		effects.append({"type": EffectPrimitivesData.GRANT_STEALTH})

	# Feel No Pain
	var fnp_regex = RegEx.new()
	fnp_regex.compile("feel no pain (\\d)\\+")
	var fnp_match = fnp_regex.search(t)
	if fnp_match:
		effects.append({"type": EffectPrimitivesData.GRANT_FNP, "value": int(fnp_match.get_string(1))})

	# --- Critical Threshold ---

	# Crit hit on X+
	var crit_regex = RegEx.new()
	crit_regex.compile("(?:unmodified )?hit roll of (\\d)\\+ scores a critical hit")
	var crit_match = crit_regex.search(t)
	if crit_match:
		effects.append({"type": EffectPrimitivesData.CRIT_HIT_ON, "value": int(crit_match.get_string(1))})

	# Crit wound on X+
	var crit_wound_regex = RegEx.new()
	crit_wound_regex.compile("(?:unmodified )?wound roll of (\\d)\\+ scores a critical wound")
	var crit_wound_match = crit_wound_regex.search(t)
	if crit_wound_match:
		effects.append({"type": EffectPrimitivesData.CRIT_WOUND_ON, "value": int(crit_wound_match.get_string(1))})

	# --- Re-rolls ---

	# Re-roll hit rolls
	if "re-roll the hit roll" in t or "re-roll hit rolls" in t:
		effects.append({"type": EffectPrimitivesData.REROLL_HITS, "scope": "all"})
	elif "re-roll hit rolls of 1" in t:
		effects.append({"type": EffectPrimitivesData.REROLL_HITS, "scope": "ones"})

	# Re-roll wound rolls
	if "re-roll the wound roll" in t or "re-roll wound rolls" in t:
		effects.append({"type": EffectPrimitivesData.REROLL_WOUNDS, "scope": "all"})
	elif "re-roll wound rolls of 1" in t:
		effects.append({"type": EffectPrimitivesData.REROLL_WOUNDS, "scope": "ones"})

	# Re-roll saves
	if "re-roll the saving throw" in t or "re-roll saving throws" in t:
		effects.append({"type": EffectPrimitivesData.REROLL_SAVES, "scope": "all"})

	# --- Movement/Eligibility ---

	# Fall back and shoot
	if "eligible to shoot" in t and "fell back" in t:
		effects.append({"type": EffectPrimitivesData.FALL_BACK_AND_SHOOT})

	# Fall back and charge
	if "eligible to" in t and "charge" in t and "fell back" in t:
		effects.append({"type": EffectPrimitivesData.FALL_BACK_AND_CHARGE})

	# --- If no effects were mapped, mark as custom/unimplemented ---

	if effects.is_empty():
		effects.append({"type": "custom:unmapped", "description": effect_text})

	return effects

func _extract_numeric_value(text: String, after_word: String) -> int:
	"""Extract a numeric value from text after a specific word."""
	var idx = text.find(after_word)
	if idx == -1:
		return 0
	var after = text.substr(idx + after_word.length()).strip_edges()
	# Find first digit
	for i in range(after.length()):
		if after[i].is_valid_int():
			return int(after[i])
	return 1

# ============================================================================
# RESTRICTION PARSING
# ============================================================================

func _parse_restrictions(restriction_text: String, strat_type: String) -> Dictionary:
	"""Parse restriction text into structured restriction data."""
	var result = {
		"once_per": "phase"  # Default: once per phase (most common)
	}

	var t = restriction_text.to_lower()

	if "once per battle" in t:
		result.once_per = "battle"
	elif "once per turn" in t:
		result.once_per = "turn"
	elif "once per phase" in t:
		result.once_per = "phase"

	# Epic Deed stratagems are once per battle by default
	if "Epic Deed" in strat_type:
		if not "once per" in t:
			result.once_per = "battle"

	return result

# ============================================================================
# UTILITY: CHECK IF UNIT MATCHES TARGET CONDITIONS
# ============================================================================

static func unit_matches_target(unit: Dictionary, target: Dictionary, context: Dictionary = {}) -> bool:
	"""Check if a unit matches the target conditions of a stratagem."""
	var conditions = target.get("conditions", [])
	var keywords = unit.get("meta", {}).get("keywords", [])
	var flags = unit.get("flags", {})

	for condition in conditions:
		if condition.begins_with("keyword:"):
			var required_kw = condition.substr(8)
			var found = false
			for kw in keywords:
				if kw.to_upper() == required_kw.to_upper():
					found = true
					break
			if not found:
				return false

		elif condition == "is_target_of_attack":
			# This is context-dependent; the unit must be a current target
			if not context.get("is_target_of_attack", false):
				return false

		elif condition == "not_shot":
			if flags.get("has_shot", false):
				return false

		elif condition == "not_fought":
			if flags.get("has_fought", false):
				return false

		elif condition == "below_starting_strength":
			# Unit must be below starting strength (some models destroyed)
			var total_models = unit.get("models", []).size()
			var alive_models = 0
			for model in unit.get("models", []):
				if model.get("alive", true):
					alive_models += 1
			if alive_models >= total_models:
				return false

		elif condition == "fell_back_this_phase":
			if not flags.get("fell_back", false):
				return false

		elif condition == "charged_this_turn":
			if not flags.get("charged_this_turn", false):
				return false

		elif condition == "in_engagement_range":
			if not flags.get("in_engagement", false) and not context.get("in_engagement_range", false):
				return false

		elif condition == "on_objective":
			if not context.get("on_objective", false):
				return false

	return true

# ============================================================================
# UTILITY: GET AVAILABLE FACTION STRATAGEMS FOR TRIGGER
# ============================================================================

static func get_faction_stratagems_for_trigger(all_stratagems: Dictionary, player: int, trigger: String, phase_name: String, is_your_turn: bool, context: Dictionary = {}) -> Array:
	"""
	Get faction stratagems available for a specific trigger point.
	Filters by: trigger match, phase match, turn match, and 'implemented' flag.
	Returns array of stratagem dictionaries.
	"""
	var available: Array = []

	for strat_id in all_stratagems:
		var strat = all_stratagems[strat_id]

		# Only include implemented faction stratagems
		if strat.get("faction_id", "") == "":
			continue  # Skip core stratagems (handled separately)
		if not strat.get("implemented", false):
			continue

		# Check trigger
		if strat.timing.trigger != trigger:
			continue

		# Check turn timing
		match strat.timing.turn:
			"your":
				if not is_your_turn:
					continue
			"opponent":
				if is_your_turn:
					continue
			"either":
				pass

		# Check phase
		if strat.timing.phase != "any" and strat.timing.phase != phase_name:
			if "_or_" in strat.timing.phase:
				var valid_phases = strat.timing.phase.split("_or_")
				if phase_name not in valid_phases:
					continue
			else:
				continue

		available.append(strat)

	return available
