class_name AbilityRegistry
extends RefCounted

## Structured weapon-ability registry (ISS-003).
##
## Weapon abilities are stored in army JSON as structured entries:
##   "abilities": [
##     {"id": "rapid_fire", "x": 1},
##     {"id": "anti", "keyword": "INFANTRY", "threshold": 4},
##     {"id": "devastating_wounds"}
##   ]
## The legacy comma-separated `special_rules` string is kept for display and
## as a fallback for un-converted data (synthetic test weapons, user files).
##
## This registry is the single source of truth for:
##   - which ability ids exist (unknown ids are LOAD ERRORS, not silent no-ops)
##   - parsing legacy strings / keyword tokens into structured entries
##   - rendering structured entries back to the canonical display string
##
## RulesEngine.get_weapon_profile() attaches the structured list to every
## weapon profile as profile["abilities"], and — when a weapon carries
## structured data — synthesizes the engine-facing `special_rules` string
## from it, so structured data is authoritative end to end.
## Validated at army load (ArmyListManager) and enforced by
## tests/test_iss003_ability_schema.gd.

## id -> {params: {name: TYPE}} . Param values are validated on load.
## Includes the 11e-forward ids (cleave, close_quarters, one_shot) so data
## can adopt them ahead of the rules implementation (ISS-047).
const REGISTRY := {
	"anti": {"params": {"keyword": TYPE_STRING, "threshold": TYPE_INT}},
	"assault": {"params": {}},
	"blast": {"params": {}},
	"cleave": {"params": {"x": TYPE_INT}},
	"close_quarters": {"params": {}},
	"devastating_wounds": {"params": {}},
	"extra_attacks": {"params": {}},
	"hazardous": {"params": {}},
	"heavy": {"params": {}},
	"ignores_cover": {"params": {}},
	"indirect_fire": {"params": {}},
	"lance": {"params": {}},
	"lethal_hits": {"params": {}},
	"melta": {"params": {"x": TYPE_INT}},
	"one_shot": {"params": {}},
	"pistol": {"params": {}},
	"precision": {"params": {}},
	"psychic": {"params": {}},
	"rapid_fire": {"params": {"x": TYPE_INT}},
	"sustained_hits": {"params": {"x": TYPE_INT, "dice": TYPE_BOOL}},
	"torrent": {"params": {}},
	"twin_linked": {"params": {}},
}

## Legacy display token -> id, for tokens without numeric/keyword parameters.
const _PLAIN_TOKENS := {
	"assault": "assault",
	"blast": "blast",
	"close-quarters": "close_quarters",
	"close quarters": "close_quarters",
	"devastating wounds": "devastating_wounds",
	"extra attacks": "extra_attacks",
	"hazardous": "hazardous",
	"heavy": "heavy",
	"ignores cover": "ignores_cover",
	"indirect fire": "indirect_fire",
	"lance": "lance",
	"lethal hits": "lethal_hits",
	"one shot": "one_shot",
	"pistol": "pistol",
	"precision": "precision",
	"psychic": "psychic",
	"torrent": "torrent",
	"twin-linked": "twin_linked",
	"twin linked": "twin_linked",
}


## Parse one legacy token (e.g. "rapid fire 1", "anti-infantry 4+") into a
## structured entry. Unknown tokens return {"id": "__unknown__", "raw": token}.
static func parse_token(token: String) -> Dictionary:
	var t := token.strip_edges().to_lower()
	if t == "":
		return {}
	if _PLAIN_TOKENS.has(t):
		return {"id": _PLAIN_TOKENS[t]}

	var rx := RegEx.new()
	# anti-<keyword> <n>+   (keyword is a single identifier, matching the
	# legacy RulesEngine regex "anti-([a-z_]+)\s+(\d+\+)")
	rx.compile("^anti-([a-z_]+)\\s+(\\d+)\\+$")
	var m := rx.search(t)
	if m:
		return {"id": "anti", "keyword": m.get_string(1).to_upper(), "threshold": m.get_string(2).to_int()}

	rx.compile("^rapid fire\\s+(\\d+)$")
	m = rx.search(t)
	if m:
		return {"id": "rapid_fire", "x": m.get_string(1).to_int()}

	# sustained hits X or DX (legacy regex "sustained hits\s*(d?)(\d+)")
	rx.compile("^sustained hits\\s+(d?)(\\d+)$")
	m = rx.search(t)
	if m:
		var entry := {"id": "sustained_hits", "x": m.get_string(2).to_int()}
		if m.get_string(1) == "d":
			entry["dice"] = true
		return entry

	rx.compile("^melta\\s+(\\d+)$")
	m = rx.search(t)
	if m:
		return {"id": "melta", "x": m.get_string(1).to_int()}

	rx.compile("^cleave\\s+(\\d+)$")
	m = rx.search(t)
	if m:
		return {"id": "cleave", "x": m.get_string(1).to_int()}

	return {"id": "__unknown__", "raw": token.strip_edges()}


## Parse a legacy comma-separated special_rules string into structured entries.
static func parse_special_rules(text: String) -> Array:
	var out: Array = []
	for part in text.split(","):
		var entry := parse_token(part)
		if not entry.is_empty():
			out.append(entry)
	return out


## Build the structured ability list for a weapon dict. Structured data wins;
## otherwise fall back to parsing the legacy string and keywords array.
static func from_weapon(weapon: Dictionary) -> Array:
	var abilities = weapon.get("abilities", [])
	if abilities is Array and not abilities.is_empty():
		return abilities.duplicate(true)
	var out: Array = []
	var seen := {}
	for entry in parse_special_rules(str(weapon.get("special_rules", ""))):
		if entry.get("id") != "__unknown__" and not seen.has(entry.id):
			seen[entry.id] = true
			out.append(entry)
	# Some data (and legacy WEAPON_PROFILES) carries keyword tokens instead,
	# e.g. ["PISTOL", "RAPID FIRE 1"].
	for kw in weapon.get("keywords", []):
		var entry := parse_token(str(kw))
		if not entry.is_empty() and entry.get("id") != "__unknown__" and not seen.has(entry.id):
			seen[entry.id] = true
			out.append(entry)
	return out


## Validate structured entries. Returns an array of human-readable errors
## (empty = valid). Unknown ids and badly-typed params are errors.
static func validate(abilities: Array) -> Array:
	var errors: Array = []
	for entry in abilities:
		if not entry is Dictionary:
			errors.append("ability entry is not a Dictionary: %s" % str(entry))
			continue
		var id = str(entry.get("id", ""))
		if id == "" or not REGISTRY.has(id):
			errors.append("unknown ability id '%s' (entry: %s)" % [id, str(entry)])
			continue
		var params: Dictionary = REGISTRY[id]["params"]
		for key in entry:
			if key == "id":
				continue
			if not params.has(key):
				errors.append("ability '%s' has unexpected param '%s'" % [id, key])
			elif typeof(entry[key]) != params[key] and not (params[key] == TYPE_INT and typeof(entry[key]) == TYPE_FLOAT and entry[key] == floor(entry[key])):
				# JSON parses ints as floats; accept whole floats for int params.
				errors.append("ability '%s' param '%s' has wrong type (%s)" % [id, key, type_string(typeof(entry[key]))])
	return errors


## Render structured entries back to the canonical legacy display string
## (lowercase, comma-separated) consumed by the engine's string matchers and
## shown in the UI.
static func to_display_string(abilities: Array) -> String:
	var parts: Array = []
	for entry in abilities:
		if not entry is Dictionary:
			continue
		var id = str(entry.get("id", ""))
		match id:
			"anti":
				parts.append("anti-%s %d+" % [str(entry.get("keyword", "")).to_lower(), int(entry.get("threshold", 0))])
			"rapid_fire":
				parts.append("rapid fire %d" % int(entry.get("x", 1)))
			"sustained_hits":
				if entry.get("dice", false):
					parts.append("sustained hits d%d" % int(entry.get("x", 1)))
				else:
					parts.append("sustained hits %d" % int(entry.get("x", 1)))
			"melta":
				parts.append("melta %d" % int(entry.get("x", 1)))
			"cleave":
				parts.append("cleave %d" % int(entry.get("x", 1)))
			"__unknown__":
				parts.append(str(entry.get("raw", "")))
			_:
				# Reverse the plain-token map: id -> first display token.
				var display := ""
				for token in _PLAIN_TOKENS:
					if _PLAIN_TOKENS[token] == id:
						display = token
						break
				parts.append(display if display != "" else id)
	return ", ".join(parts)


## True if the structured list contains the given ability id.
static func has_ability(abilities: Array, id: String) -> bool:
	for entry in abilities:
		if entry is Dictionary and str(entry.get("id", "")) == id:
			return true
	return false


## Fetch a param from the first entry with the given id.
static func get_param(abilities: Array, id: String, key: String, default = null):
	for entry in abilities:
		if entry is Dictionary and str(entry.get("id", "")) == id:
			return entry.get(key, default)
	return default
