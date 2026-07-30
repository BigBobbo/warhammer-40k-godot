extends RefCounted
class_name UnitLoadoutResolver

# UnitLoadoutResolver — "which of the datasheet's weapons does THIS unit
# actually carry?"
#
# Why this exists
# ---------------
# `unit.meta.weapons` is the datasheet's full weapon MENU — every profile the
# datasheet lists, including options this particular model never took. A
# Battlewagon's menu is Big shoota / Kannon / Killkannon / Lobba / Zzap gun /
# Deff rolla / Grabbin' klaw / Tracks and wheels / Wreckin' ball, but the one in
# the tutorial roster is only armed with a Kannon, a Lobba, a Deff rolla, a
# Grabbin' klaw and a Wreckin' ball. Rendering `meta.weapons` verbatim (which is
# what every datasheet UI used to do) showed the player weapons the unit does
# not have.
#
# The roster DOES record the chosen loadout: `unit.meta.wargear` is a list of
# "1x Deff rolla" / "1x Kannon" / "1x 'Ard Case" style entries. That, plus the
# datasheet's *base* kit (weapons a model always has, which are implicit and so
# never appear in wargear — e.g. the Battlewagon's Tracks and wheels), is enough
# to narrow the menu down to the real loadout.
#
# Base-kit weapons come from `data/40kdc/unitCompositions.json`
# (`models[].default_weapon_ids`), matched by slugified datasheet name.
#
# Safety posture — this only ever narrows, and only when it is confident:
#   * no parseable wargear weapon for the unit  -> return the menu untouched
#   * the composition data is missing/unreadable -> base kit is simply empty
#   * the filter would return nothing            -> return the menu untouched
# So a roster we cannot read is displayed exactly as it is today.
#
# NOTE (scope): this is a DISPLAY resolver. The shooting/fight engine resolves
# per-model loadouts separately in RulesEngine._ensure_loadout_resolved(), which
# deliberately skips single-model units (vehicles/characters) — so a Battlewagon
# can still be *offered* its unequipped guns in the Shooting phase. That is a
# separate (engine-side) fix and is intentionally not changed here.

const COMPOSITIONS_PATH := "res://data/40kdc/unitCompositions.json"

# Profile-split separators used in weapon names ("Kannon – Frag", "Guardian
# spear – Melee"). The wargear entry only ever names the base weapon.
const PROFILE_SEPARATORS := [" – ", " — ", " - "]

# 40kdc unit_id -> Array[String] of default (base-kit) weapon ids.
static var _defaults_by_unit: Dictionary = {}
# 40kdc unit_id -> {model_name_slug: Array[String] of default weapon ids}. Same
# data as above but WITHOUT flattening the per-model split, so a caller can ask
# "what is a Boss Nob equipped with?" separately from "what is a Boy equipped
# with?" (Boyz: Boss Nob = big choppa + slugga, Boy = slugga + choppa).
static var _defaults_by_unit_model: Dictionary = {}
# 40kdc unit_id -> ordered Array of {name, min, max} — the datasheet's unit
# composition ("1 Boss Nob", then "9-19 Boy"). Lets a caller work out which role
# a model plays from its POSITION when the unit carries no model_profiles.
static var _roles_by_unit: Dictionary = {}
static var _compositions_loaded: bool = false


## The subset of the unit's datasheet weapons it is actually equipped with.
## Returns the untouched weapon list whenever the loadout cannot be resolved.
static func get_equipped_weapons(unit: Dictionary) -> Array:
	var meta: Dictionary = unit.get("meta", {}) if typeof(unit.get("meta", {})) == TYPE_DICTIONARY else {}
	var weapons = meta.get("weapons", unit.get("weapons", []))
	if typeof(weapons) != TYPE_ARRAY or weapons.is_empty():
		return []

	# Every slug this datasheet's weapons answer to (full name AND base name, so
	# a wargear entry of "Kannon" matches both "Kannon – Frag" and "Kannon – Shell").
	var weapon_slugs := {}
	for w in weapons:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var wname := str(w.get("name", ""))
		weapon_slugs[_slug(wname)] = true
		weapon_slugs[_slug(_base_name(wname))] = true

	# Wargear entries that name one of this datasheet's weapons. Entries that
	# name a role ("9x Kommando"), a non-weapon upgrade ("1x 'Ard Case") or a
	# weapon from another datasheet are ignored.
	var selected := {}
	for s in _parse_wargear_slugs(meta.get("wargear", [])):
		if weapon_slugs.has(s):
			selected[s] = true

	if selected.is_empty():
		# No usable loadout signal — show the datasheet as-is rather than guess.
		return weapons

	var allowed := selected.duplicate()
	for s in _base_kit_slugs(unit, meta, weapons, selected):
		allowed[s] = true

	var out: Array = []
	for w in weapons:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var wname := str(w.get("name", ""))
		if allowed.has(_slug(wname)) or allowed.has(_slug(_base_name(wname))):
			out.append(w)

	if out.is_empty():
		# Defensive: never blank out the weapons section.
		print("[LOADOUT-UI] %s: filter matched nothing, showing full datasheet menu" % str(meta.get("name", "?")))
		return weapons
	return out


## The datasheet's DEFAULT kit for one model role, intersected with `weapon_names`.
##
## `unit_name`  — the datasheet name ("Boyz").
## `role_names` — candidate names for the model's role, most specific first
##                (its `model_type` key "boss_nob" AND its model_profiles label
##                "Boss Nob" — both slugify to the composition's "Boss Nob").
## `weapon_names` — the datasheet weapon names to filter (already narrowed to one
##                type by the caller, e.g. every Melee weapon on the datasheet).
##
## Returns the subset of `weapon_names` the role is equipped with by default, in
## the order given. Empty when the composition doesn't know this datasheet, the
## role can't be matched, or the role's kit has nothing of this weapon type — all
## of which the caller must treat as "cannot resolve", never as "no weapons".
##
## This is the answer to "what does a model of this role ACTUALLY carry?" when
## the roster's wargear string is silent — which it usually is for melee.
static func get_model_default_weapon_names(unit_name: String, role_names: Array, weapon_names: Array) -> Array:
	var unit_slug := _slug(unit_name)
	if unit_slug == "":
		return []
	_ensure_compositions_loaded()
	var per_model = _defaults_by_unit_model.get(unit_slug, {})
	if typeof(per_model) != TYPE_DICTIONARY or per_model.is_empty():
		return []

	# Match the model to a composition role. A single-role datasheet needs no
	# match at all (there is only one thing a model can be).
	var role_key := ""
	for candidate in role_names:
		var s := _slug(str(candidate))
		if s != "" and per_model.has(s):
			role_key = s
			break
	if role_key == "" and per_model.size() == 1:
		role_key = str(per_model.keys()[0])
	if role_key == "":
		return []

	# 40kdc disambiguates ids that clash across datasheets by appending the unit
	# slug ("choppa-tankbustas"); strip it back off, as _base_kit_slugs does.
	var default_slugs := {}
	for id in per_model[role_key]:
		var s := str(id)
		if s.ends_with("-" + unit_slug):
			s = s.substr(0, s.length() - unit_slug.length() - 1)
		if s != "":
			default_slugs[s] = true

	var out: Array = []
	for wname in weapon_names:
		var n := str(wname)
		# Match the full name AND the base name, so the id "guardian-spear"
		# matches the profile-split weapon "Guardian spear – Melee".
		if default_slugs.has(_slug(n)) or default_slugs.has(_slug(_base_name(n))):
			if n not in out:
				out.append(n)
	return out


## The datasheet's unit composition as an ordered [{name, min, max}] — leader
## model first, bulk troops last, exactly as printed ("1 Boss Nob", "9-19 Boy").
## Empty when the composition data doesn't cover this datasheet.
static func get_model_roles(unit_name: String) -> Array:
	var unit_slug := _slug(unit_name)
	if unit_slug == "":
		return []
	_ensure_compositions_loaded()
	var roles = _roles_by_unit.get(unit_slug, [])
	return roles if typeof(roles) == TYPE_ARRAY else []


## Convenience for callers that only need names (tests, logging).
static func get_equipped_weapon_names(unit: Dictionary) -> Array:
	var names: Array = []
	for w in get_equipped_weapons(unit):
		if typeof(w) == TYPE_DICTIONARY:
			names.append(str(w.get("name", "")))
	return names


# ── wargear parsing ─────────────────────────────────────────────────

# "1x Deff rolla" -> "deff-rolla"; "2x Loota (KMB)" -> "loota";
# "Shield-Captain (Shield), Praesidium Shield" -> ["shield-captain", "praesidium-shield"].
static func _parse_wargear_slugs(wargear) -> Array:
	var out: Array = []
	if typeof(wargear) != TYPE_ARRAY:
		return out
	for entry in wargear:
		for part in str(entry).split(","):
			var txt := str(part).strip_edges()
			if txt == "":
				continue
			# Strip a leading "Nx " count if present (some rosters omit it).
			var space := txt.find(" ")
			if space > 0:
				var head := txt.substr(0, space)
				if head.ends_with("x") and head.substr(0, head.length() - 1).is_valid_int():
					txt = txt.substr(space + 1).strip_edges()
			# Strip a trailing parenthetical qualifier ("Loota (KMB)").
			var paren := txt.find("(")
			if paren > 0:
				txt = txt.substr(0, paren).strip_edges()
			var s := _slug(txt)
			if s != "" and s not in out:
				out.append(s)
	return out


# ── base kit (weapons the model always has) ─────────────────────────

# The 40kdc default weapon ids for this datasheet, minus any that the roster's
# wargear clearly REPLACED.
static func _base_kit_slugs(unit: Dictionary, meta: Dictionary, weapons: Array, selected: Dictionary) -> Array:
	var unit_slug := _slug(str(meta.get("name", "")))
	if unit_slug == "":
		return []
	_ensure_compositions_loaded()
	var raw = _defaults_by_unit.get(unit_slug, [])
	if typeof(raw) != TYPE_ARRAY or raw.is_empty():
		return []

	# 40kdc disambiguates weapon ids that clash across datasheets by appending
	# the unit slug ("big-shoota-warboss-in-mega-armour"). Strip it back off.
	var defaults: Array = []
	for id in raw:
		var s := str(id)
		if s.ends_with("-" + unit_slug):
			s = s.substr(0, s.length() - unit_slug.length() - 1)
		if s != "" and s not in defaults:
			defaults.append(s)

	# Multi-model units: per-model counts make "was this default swapped out?"
	# undecidable from unit-level wargear, so keep the whole base kit (erring
	# towards showing a weapon rather than hiding one the player owns).
	if unit.get("models", []).size() != 1:
		return defaults

	# Single model (vehicle / character): if the roster picked exactly as many
	# weapons of a type as the base kit has of that type, treat it as a straight
	# swap and drop the unpicked base weapon — a Warboss with a power klaw no
	# longer has the default big choppa. When it picked MORE (a Battlewagon
	# bolting a deff rolla, grabbin' klaw and wreckin' ball onto its one base
	# melee weapon) the picks are additive and Tracks and wheels stays.
	var type_of := _weapon_type_index(weapons)
	var selected_by_type := {}
	for s in selected:
		var t := str(type_of.get(s, ""))
		selected_by_type[t] = int(selected_by_type.get(t, 0)) + 1
	var defaults_by_type := {}
	for s in defaults:
		var t := str(type_of.get(s, ""))
		defaults_by_type[t] = int(defaults_by_type.get(t, 0)) + 1

	var kept: Array = []
	for s in defaults:
		if selected.has(s):
			continue  # already allowed via wargear
		var t := str(type_of.get(s, ""))
		var n_sel := int(selected_by_type.get(t, 0))
		if n_sel > 0 and n_sel == int(defaults_by_type.get(t, 0)):
			print("[LOADOUT-UI] %s: base '%s' treated as replaced by the roster's %s pick(s)" % [
				str(meta.get("name", "?")), s, t])
			continue
		kept.append(s)
	return kept


# slug (full name AND base name) -> lowercased weapon type ("ranged"/"melee").
static func _weapon_type_index(weapons: Array) -> Dictionary:
	var out := {}
	for w in weapons:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var wname := str(w.get("name", ""))
		var t := str(w.get("type", "")).to_lower()
		out[_slug(wname)] = t
		var b := _slug(_base_name(wname))
		if not out.has(b):
			out[b] = t
	return out


static func _ensure_compositions_loaded() -> void:
	if _compositions_loaded:
		return
	_compositions_loaded = true
	if not FileAccess.file_exists(COMPOSITIONS_PATH):
		print("[LOADOUT-UI] %s not found — base-kit weapons unavailable" % COMPOSITIONS_PATH)
		return
	var f := FileAccess.open(COMPOSITIONS_PATH, FileAccess.READ)
	if f == null:
		print("[LOADOUT-UI] cannot open %s (err %d)" % [COMPOSITIONS_PATH, FileAccess.get_open_error()])
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		print("[LOADOUT-UI] %s did not parse to an array — base-kit weapons unavailable" % COMPOSITIONS_PATH)
		return
	for entry in parsed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var uid := str(entry.get("unit_id", ""))
		if uid == "":
			continue
		var ids: Array = _defaults_by_unit.get(uid, [])
		# 31 unit_ids appear more than once (datasheet variants sharing a slug).
		# The flattened base kit above merges them — that only ever widens a
		# "which weapons might this unit have?" answer. The per-ROLE data must
		# not: merging two variants' kits, or stacking their composition lines,
		# would hand a model a weapon from the other variant and break the
		# positional role maths. First entry wins.
		var variant_seen := _roles_by_unit.has(uid) or _defaults_by_unit_model.has(uid)
		var per_model: Dictionary = {}
		var roles: Array = []
		for m in entry.get("models", []):
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var role_slug := _slug(str(m.get("name", "")))
			if role_slug != "":
				roles.append({
					"name": str(m.get("name", "")),
					"min": int(m.get("min", 0)),
					"max": int(m.get("max", m.get("min", 0))),
				})
			var role_ids: Array = per_model.get(role_slug, [])
			for wid in m.get("default_weapon_ids", []):
				var s := str(wid)
				if s == "":
					continue
				if s not in ids:
					ids.append(s)
				if role_slug != "" and s not in role_ids:
					role_ids.append(s)
			if role_slug != "" and not role_ids.is_empty():
				per_model[role_slug] = role_ids
		if not ids.is_empty():
			_defaults_by_unit[uid] = ids
		if not variant_seen:
			if not per_model.is_empty():
				_defaults_by_unit_model[uid] = per_model
			if not roles.is_empty():
				_roles_by_unit[uid] = roles
	print("[LOADOUT-UI] base kits loaded for %d datasheets (%d with per-model roles)" % [
		_defaults_by_unit.size(), _defaults_by_unit_model.size()])


# ── name normalisation ──────────────────────────────────────────────

## "Kannon – Frag" -> "Kannon". Leaves names without a profile suffix alone.
static func _base_name(n: String) -> String:
	for sep in PROFILE_SEPARATORS:
		var idx := n.find(sep)
		if idx > 0:
			return n.substr(0, idx)
	return n


## "Grabbin' klaw" -> "grabbin-klaw", "'Ard Case" -> "ard-case".
## Apostrophes are dropped (never a separator) to match 40kdc's id style.
static func _slug(s: String) -> String:
	var out := ""
	var prev_dash := true  # true at the start so leading separators are eaten
	var lower := s.to_lower()
	for i in lower.length():
		var cp := lower.unicode_at(i)
		if (cp >= 97 and cp <= 122) or (cp >= 48 and cp <= 57):
			out += String.chr(cp)
			prev_dash = false
		elif cp == 39 or cp == 0x2019:  # ' and ’
			continue
		elif not prev_dash:
			out += "-"
			prev_dash = true
	return out.rstrip("-")
