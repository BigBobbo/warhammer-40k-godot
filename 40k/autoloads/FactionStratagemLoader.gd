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

# Normalise a detachment name for comparison: lowercase, replace non-breaking
# space (U+00A0) with regular space, strip surrounding whitespace. Roster JSONs
# may have been hand-edited and contain NBSP characters (issue #366); without
# this normalisation a string compare fails silently and all detachment-gated
# stratagems are dropped.
static func _normalise_detachment_name(s: String) -> String:
	if s == "":
		return ""
	# U+00A0 is encoded as the multi-byte sequence " " in GDScript strings.
	return s.replace(" ", " ").strip_edges().to_lower()

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
	# 11e note: the 40kdc-generated Factions.csv names the Space Marines
	# faction "Adeptus Astartes" and Imperial Agents "Agents of the
	# Imperium" — keep the legacy names (used by armies/*.json) resolving
	# to the same codes.
	_faction_name_to_code["space marines"] = "SM"
	_faction_name_to_code["Space Marines"] = "SM"
	_faction_name_to_code["adeptus astartes"] = "SM"
	_faction_name_to_code["Adeptus Astartes"] = "SM"
	_faction_name_to_code["imperial agents"] = "AoI"
	_faction_name_to_code["Imperial Agents"] = "AoI"
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

	# Brand-new 11e factions: the 40kdc dataset promotes Space Marine
	# chapters to first-class factions. Codes must stay in sync with
	# NEW_FACTION_CODES in scripts/40kdc/generate-stratagems.mjs (which
	# writes them into Factions.csv).
	_faction_name_to_code["black templars"] = "BT"
	_faction_name_to_code["Black Templars"] = "BT"
	_faction_name_to_code["blood angels"] = "BA"
	_faction_name_to_code["Blood Angels"] = "BA"
	_faction_name_to_code["crimson fists"] = "CF"
	_faction_name_to_code["Crimson Fists"] = "CF"
	_faction_name_to_code["dark angels"] = "DA"
	_faction_name_to_code["Dark Angels"] = "DA"
	_faction_name_to_code["deathwatch"] = "DW"
	_faction_name_to_code["Deathwatch"] = "DW"
	_faction_name_to_code["imperial fists"] = "IF"
	_faction_name_to_code["Imperial Fists"] = "IF"
	_faction_name_to_code["iron hands"] = "IH"
	_faction_name_to_code["Iron Hands"] = "IH"
	_faction_name_to_code["raven guard"] = "RG"
	_faction_name_to_code["Raven Guard"] = "RG"
	_faction_name_to_code["salamanders"] = "SAL"
	_faction_name_to_code["Salamanders"] = "SAL"
	_faction_name_to_code["space wolves"] = "SW"
	_faction_name_to_code["Space Wolves"] = "SW"
	_faction_name_to_code["ultramarines"] = "UM"
	_faction_name_to_code["Ultramarines"] = "UM"
	_faction_name_to_code["white scars"] = "WS"
	_faction_name_to_code["White Scars"] = "WS"

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

		# Filter by detachment if specified.
		# Issue #366: roster JSONs may store detachment names with NBSP (U+00A0)
		# instead of regular spaces (e.g. `Adeptus_Custodes_1995_Mar_7.json` had
		# "Lions of the Emperor"). Plain `==` then fails silently and
		# every detachment-stratagem load is dropped. Normalise both sides via
		# `_normalise_detachment_name` (lowercase, NBSP→space, strip edges).
		if detachment_name != "" and row_detachment != "" and \
				_normalise_detachment_name(row_detachment) != _normalise_detachment_name(detachment_name):
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
	# Optional 11e (40kdc) columns — absent in legacy CSVs.
	var csv_timing = row.get("timing", "").strip_edges()
	var csv_effects_json = row.get("effects_json", "").strip_edges()

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

	# Map effects: prefer the generator-compiled effects_json column
	# (EffectPrimitives-shaped dicts passed straight through, marking the
	# stratagem implemented); fall back to the legacy effect-text regexes.
	var effects = _parse_effects_json(csv_effects_json)
	if effects.is_empty():
		effects = _map_effects(parsed_desc.get("effect_text", ""))

	# Parse restrictions from RESTRICTIONS text
	var restrictions = _parse_restrictions(parsed_desc.get("restriction_text", ""), csv_type)
	# Optional "timing" column drives once-per limits directly (overrides
	# the text-derived value when present).
	_apply_timing_column(restrictions, csv_timing)

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

	# #359: split off "excluding X" / "except X" clauses BEFORE keyword matching, so
	# words like "Vehicle" / "Monster" inside the exclusion don't get parsed as required.
	# Excluded keywords become "not_keyword:X" conditions checked separately.
	var split = _strip_excluding_clauses(t)
	var inclusive_t: String = split.stripped
	var excluded_keywords: Array = split.excluded_keywords
	for ek in excluded_keywords:
		result.conditions.append(ek)

	# Determine owner — only based on inclusive text (the exclusion clause may also
	# contain words like "enemy" e.g. "excluding enemy CHARACTERS").
	if "enemy" in inclusive_t:
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
		# Silent Hunters (Anathema Psykana) stratagems target specific
		# Sisters of Silence datasheets by keyword.
		["vigilators", "keyword:VIGILATORS"],
		["prosecutors", "keyword:PROSECUTORS"],
		["witchseekers", "keyword:WITCHSEEKERS"],
		["anathema psykana", "keyword:ANATHEMA PSYKANA"],
	]

	for pattern in keyword_patterns:
		if pattern[0] in inclusive_t:
			result.conditions.append(pattern[1])

	# Faction keyword requirements
	if "adeptus astartes" in inclusive_t:
		result.conditions.append("keyword:ADEPTUS ASTARTES")
	if "adeptus custodes" in inclusive_t:
		result.conditions.append("keyword:ADEPTUS CUSTODES")
	if "orks" in inclusive_t:
		result.conditions.append("keyword:ORKS")

	# Special conditions — also derived from the inclusive zone only.
	if "was selected as the target" in inclusive_t:
		result.conditions.append("is_target_of_attack")
	if "not been selected to shoot" in inclusive_t:
		result.conditions.append("not_shot")
	if "not been selected to fight" in inclusive_t:
		result.conditions.append("not_fought")
	if "below half-strength" in inclusive_t or "below its starting strength" in inclusive_t:
		result.conditions.append("below_starting_strength")
	if "fell back this phase" in inclusive_t:
		result.conditions.append("fell_back_this_phase")
	if "made a charge move this turn" in inclusive_t:
		result.conditions.append("charged_this_turn")
	if "within engagement range" in inclusive_t:
		result.conditions.append("in_engagement_range")
	if "within range of an objective" in inclusive_t:
		result.conditions.append("on_objective")

	return result

func _strip_excluding_clauses(t: String) -> Dictionary:
	"""Find 'excluding X' / 'except X' clauses, capture excluded keywords as
	'not_keyword:X' conditions, and return the text with those clauses removed.

	An exclusion clause runs from the marker word until the next ')', '.', or
	' that ' (typical clause separators in WH40K rules text). Returns:
	  { stripped: String, excluded_keywords: Array<String> }
	"""
	var keyword_patterns = [
		["infantry", "INFANTRY"],
		["vehicle", "VEHICLE"],
		["monster", "MONSTER"],
		["character", "CHARACTER"],
		["battleline", "BATTLELINE"],
		["terminator", "TERMINATOR"],
		["mounted", "MOUNTED"],
		["grots", "GROTS"],
		["adeptus astartes", "ADEPTUS ASTARTES"],
		["adeptus custodes", "ADEPTUS CUSTODES"],
		["orks", "ORKS"],
		["anathema psykana", "ANATHEMA PSYKANA"],
	]
	var stripped: String = t
	var excluded: Array = []

	for marker in ["excluding", "except"]:
		while true:
			var idx = stripped.find(marker)
			if idx < 0:
				break

			# Find clause end: nearest of ')', '.', ' that '. Default to end-of-string.
			var end_idx = stripped.length()
			var paren = stripped.find(")", idx)
			var period = stripped.find(".", idx)
			var that_after = stripped.find(" that ", idx)
			for cand in [paren, period, that_after]:
				if cand > idx and cand < end_idx:
					end_idx = cand

			# Capture clause text and parse excluded keywords from it.
			var clause = stripped.substr(idx, end_idx - idx)
			for pat in keyword_patterns:
				if pat[0] in clause:
					var cond = "not_keyword:%s" % pat[1]
					if not excluded.has(cond):
						excluded.append(cond)

			# Strip the clause AND the leading "(" if there's one immediately before
			# (so we don't leave a dangling "(" behind).
			var strip_start = idx
			# Walk backward past whitespace and an optional '('.
			var probe = idx - 1
			while probe >= 0 and stripped[probe] == " ":
				probe -= 1
			if probe >= 0 and stripped[probe] == "(":
				strip_start = probe

			# Include the trailing ')' if the end was a paren.
			var strip_end = end_idx
			if end_idx < stripped.length() and stripped[end_idx] == ")":
				strip_end = end_idx + 1

			stripped = stripped.substr(0, strip_start) + stripped.substr(strip_end)

	return {"stripped": stripped, "excluded_keywords": excluded}

# ============================================================================
# EFFECT MAPPING
# ============================================================================

static func _parse_effects_json(csv_effects_json: String) -> Array:
	"""Parse the optional effects_json CSV column: a JSON array of
	EffectPrimitives-shaped effect dicts emitted by the 40kdc generator
	(scripts/40kdc/generate-stratagems.mjs). Passed straight through as the
	stratagem's effects when non-empty. Returns [] when the column is
	absent/empty/invalid so the caller falls back to text mapping."""
	if csv_effects_json == "":
		return []
	var parsed = JSON.parse_string(csv_effects_json)
	if not (parsed is Array):
		print("FactionStratagemLoader: Invalid effects_json ignored: %s" % csv_effects_json)
		return []
	var effects: Array = []
	for e in parsed:
		if not (e is Dictionary) or String(e.get("type", "")) == "":
			print("FactionStratagemLoader: Invalid effects_json entry ignored: %s" % str(e))
			return []
		# JSON numbers arrive as floats; the primitives expect ints
		# (invuln 4, FNP 5, +2 charge, ...).
		if e.has("value") and e["value"] is float and e["value"] == floor(e["value"]):
			e["value"] = int(e["value"])
		effects.append(e)
	return effects

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

	# Issue #393 AVENGE THE FALLEN (Shield Host): "add 1 to the Attacks
	# characteristic of melee weapons" — and a conditional "add 2 ... instead"
	# clause when the unit is Below Half-strength. We emit BOTH the default
	# value AND a Below-Half variant when the conditional clause is present;
	# RulesEngine picks the right one at attack time based on live unit state.
	var plus_attacks_regex = RegEx.new()
	plus_attacks_regex.compile("add (\\d) to the attacks characteristic")
	var plus_attacks_matches = plus_attacks_regex.search_all(t)
	if not plus_attacks_matches.is_empty():
		var values: Array = []
		for m in plus_attacks_matches:
			values.append(int(m.get_string(1)))
		var has_below_half_clause = ("below half-strength" in t) or ("below half strength" in t)
		if values.size() == 1:
			# Single value, no conditional clause — emit as-is.
			effects.append({"type": EffectPrimitivesData.PLUS_ATTACKS, "value": values[0], "scope": "melee"})
		elif has_below_half_clause:
			# Two clauses: default + Below-Half variant. Lower value is the
			# default; higher is the below-half override.
			values.sort()
			effects.append({"type": EffectPrimitivesData.PLUS_ATTACKS, "value": values[0], "scope": "melee"})
			effects.append({"type": EffectPrimitivesData.PLUS_ATTACKS_BELOW_HALF, "value": values[-1], "scope": "melee"})
		else:
			# Multiple values but no conditional clause — fall back to the max
			# (preserves prior behaviour for unrecognised stratagems).
			var max_bonus = 0
			for v in values:
				if v > max_bonus:
					max_bonus = v
			if max_bonus > 0:
				effects.append({"type": EffectPrimitivesData.PLUS_ATTACKS, "value": max_bonus, "scope": "melee"})

	# --- Keyword Grants ---

	# Issue #381: Detect "either [X] or [Y]" wording so we don't grant BOTH
	# LETHAL HITS AND SUSTAINED HITS for ARCHEOTECH MUNITIONS et al. With this
	# flag set, only the FIRST matching keyword is granted (sensible default;
	# follow-up should add a UI choice prompt).
	var has_either_or_choice = ("either" in t) and ("or " in t)

	# Ignores Cover
	if "[ignores cover]" in t:
		effects.append({"type": EffectPrimitivesData.GRANT_IGNORES_COVER})

	# Lethal Hits
	var lethal_hits_granted = false
	if "[lethal hits]" in t:
		effects.append({"type": EffectPrimitivesData.GRANT_LETHAL_HITS})
		lethal_hits_granted = true

	# Sustained Hits — skip if either/or already granted Lethal Hits
	if "[sustained hits" in t and not (has_either_or_choice and lethal_hits_granted):
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

	# Re-roll charge rolls (e.g. Swift Onslaught, Plummeting Descent)
	# Issue #372: previously routed through ability data only — wire the
	# stratagem text into the same primitive so 'ERE WE GO and similar
	# stratagems can grant a charge re-roll via _map_effects.
	if "re-roll the charge roll" in t or "re-roll charge rolls" in t \
			or "re-roll its charge roll" in t:
		effects.append({"type": EffectPrimitivesData.REROLL_CHARGE})

	# +N to charge roll. Wahapedia phrasing varies: "add 2 to that Charge roll",
	# "add 2 to its Charge roll", "add 2 to the Charge roll", "+2 to charge",
	# and (Issue #375 'ERE WE GO) "add 2 to Advance and Charge rolls".
	# Issue #372 unblocks 'ERE WE GO (+2) and ~12 other faction stratagems.
	var charge_regex = RegEx.new()
	charge_regex.compile("(?:add (\\d) to (?:the |its |that )?(?:advance and )?charge rolls?|\\+(\\d) to (?:the )?charge)")
	var charge_match = charge_regex.search(t)
	if charge_match:
		var raw = charge_match.get_string(1)
		if raw == "":
			raw = charge_match.get_string(2)
		var bonus = int(raw) if raw != "" else 1
		if bonus > 0:
			effects.append({"type": EffectPrimitivesData.PLUS_CHARGE, "value": bonus})

	# --- Movement/Eligibility ---

	# Fall back and shoot
	if "eligible to shoot" in t and "fell back" in t:
		effects.append({"type": EffectPrimitivesData.FALL_BACK_AND_SHOOT})

	# Fall back and charge
	if "eligible to" in t and "charge" in t and "fell back" in t:
		effects.append({"type": EffectPrimitivesData.FALL_BACK_AND_CHARGE})

	# Issue #375 MOB RULE (War Horde): "is no longer Battle-shocked" -> clear flag.
	if "is no longer battle-shocked" in t:
		effects.append({"type": EffectPrimitivesData.REMOVE_BATTLE_SHOCK})

	# Issue #375 VIGILANCE ETERNAL (Shield Host): keep objective marker control
	# even if no models within range.
	if "objective marker remains under your control" in t:
		effects.append({"type": EffectPrimitivesData.STICKY_OBJECTIVE_CONTROL})

	# Issue #375 CAREEN! (War Horde): "make a Normal or Fall Back move before
	# its Deadly Demise ability is resolved".
	if "normal or fall back move" in t and "deadly demise" in t:
		effects.append({"type": EffectPrimitivesData.DEADLY_DEMISE_MOVE})

	# Issue #375 ORKS IS NEVER BEATEN (War Horde): "do not remove it from play.
	# The destroyed model can fight after the attacking model's unit has
	# finished making attacks".
	if "do not remove it from play" in t and "can fight after" in t:
		effects.append({"type": EffectPrimitivesData.SWING_BACK_BEFORE_REMOVE})

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

static func _apply_timing_column(restrictions: Dictionary, csv_timing: String) -> void:
	"""Optional 'timing' CSV column (40kdc 11e data): drives the once-per
	limit directly instead of sniffing the RESTRICTIONS text. Empty/unknown
	values leave the text-derived restriction untouched (legacy fallback)."""
	match csv_timing:
		"once-per-phase":
			restrictions.once_per = "phase"
		"once-per-turn":
			restrictions.once_per = "turn"
		"once-per-battle":
			restrictions.once_per = "battle"
		"unlimited":
			# null = no once-per restriction (StratagemManager treats null
			# as unrestricted in _check_usage_restriction).
			restrictions.once_per = null

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

		elif condition.begins_with("not_keyword:"):
			# #359: "excluding X" clauses become not_keyword:X conditions —
			# the unit must NOT have this keyword.
			var excluded_kw = condition.substr(12)
			for kw in keywords:
				if kw.to_upper() == excluded_kw.to_upper():
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
