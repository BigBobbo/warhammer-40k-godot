extends RefCounted
## Data-driven 11e enhancement army-construction checks (WP-C46).
##
## Reads the vendored 40kdc dataset (res://data/40kdc/enhancements.json and
## detachments.json) and validates an army's enhancements against it:
##   - the enhancement belongs to the army's detachment (`detachment_id`);
##   - the bearer meets the printed restriction — the first sentence of
##     `rules_text`, "<keywords / datasheet name> model only." or
##     "... unit only (excluding <X> units).";
##   - a normal enhancement sits on a CHARACTER (not an EPIC HERO); an
##     Upgrade (`upgrade_tag`) "can be given to non-CHARACTER units" (core
##     rules, Select Enhancements) — it is NOT limited to them: any unit that
##     is not an EPIC HERO, subject to its printed restriction (e.g. the Ork
##     "Big Mek with Shokk Attack Gun model only" Upgrades), on at most three
##     units ("(one per army)" Upgrades: one unit);
##   - each enhancement goes to a different unit (one per unit);
##   - each enhancement is taken once per army;
##   - the 2-per-1000-points cap (an Upgrade counts as one choice).
##
## Restriction parsing is generic: the phrase must be fully consumed by the
## bearer's keywords and datasheet name, longest match first, with "a/b"
## words read as alternatives — so "Adeptus Custodes Infantry/Mounted",
## "grav-assault Transport", "Trusted Sentinel" and "Shield-Captain in Allarus
## Terminator Armour" all resolve without per-faction tables. Records without
## `rules_text` (the dataset's superseded 10e-era entries) carry no printed
## restriction and are checked only for CHARACTER / once-per-army / cap.
##
## Pure static module; no autoloads.

const ENHANCEMENTS_PATH := "res://data/40kdc/enhancements.json"
const DETACHMENTS_PATH := "res://data/40kdc/detachments.json"

static var _enhancements: Array = []
static var _detachments: Array = []
static var _loaded := false


static func _load_json(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("EnhancementRules11e: %s missing" % path)
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Array:
		return parsed
	if parsed is Dictionary:
		for k in ["enhancements", "detachments", "data"]:
			if parsed.get(k, null) is Array:
				return parsed[k]
	return []


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_enhancements = _load_json(ENHANCEMENTS_PATH)
	_detachments = _load_json(DETACHMENTS_PATH)
	print("EnhancementRules11e: loaded %d enhancements, %d detachments" % [_enhancements.size(), _detachments.size()])


## Normalise a name: lower case, curly apostrophes folded, NBSP -> space,
## "(one per army)" / "(upgrade)" suffixes dropped.
static func norm(name: String) -> String:
	var k := name.replace(" ", " ").replace("’", "'").replace("‘", "'").strip_edges().to_lower()
	for suffix in [" (one per army)", " (upgrade)"]:
		if k.ends_with(suffix):
			k = k.substr(0, k.length() - suffix.length()).strip_edges()
	return k


## The detachment record for a detachment display name (or id), {} if unknown.
## Codex records win over superseded ones that share a name.
static func find_detachment(name_or_id: String) -> Dictionary:
	_ensure_loaded()
	var key := norm(name_or_id)
	var best: Dictionary = {}
	for d in _detachments:
		if not d is Dictionary:
			continue
		if str(d.get("id", "")) == name_or_id or norm(str(d.get("name", ""))) == key:
			if best.is_empty() or (best.has("superseded_by_codex") and not d.has("superseded_by_codex")):
				best = d
	return best


## The enhancement record named `enh_name` in the given detachment ({} when the
## detachment does not list it). With an unknown detachment, any record of that
## name with printed rules text.
static func find_enhancement(detachment_name: String, enh_name: String) -> Dictionary:
	_ensure_loaded()
	var key := norm(enh_name)
	var det := find_detachment(detachment_name)
	var det_id := str(det.get("id", ""))
	var listed: Array = det.get("enhancement_ids", []) if not det.is_empty() else []
	var fallback: Dictionary = {}
	for e in _enhancements:
		if not e is Dictionary or norm(str(e.get("name", ""))) != key:
			continue
		if det_id != "":
			if str(e.get("detachment_id", "")) == det_id and (listed.is_empty() or str(e.get("id", "")) in listed):
				return e
		elif str(e.get("rules_text", "")) != "" and fallback.is_empty():
			fallback = e
	return fallback


## Does the dataset know an enhancement of this name in ANY detachment?
static func enhancement_exists(enh_name: String) -> bool:
	_ensure_loaded()
	var key := norm(enh_name)
	for e in _enhancements:
		if e is Dictionary and norm(str(e.get("name", ""))) == key:
			return true
	return false


## The printed bearer restriction: {phrase, scope ("model"/"unit"), excluding}.
## Empty when the record has no "... only." opening sentence.
static func parse_restriction(rec: Dictionary) -> Dictionary:
	var text := str(rec.get("rules_text", "")).replace(" ", " ").strip_edges()
	if text == "":
		return {}
	var re := RegEx.new()
	re.compile("^(.+?)\\s+(model|unit)s?\\s+only(?:\\s*\\(excluding\\s+(.+?)\\s+units?\\))?\\s*\\.")
	var m := re.search(text)
	if m == null:
		return {}
	return {"phrase": m.get_string(1).strip_edges(), "scope": m.get_string(2), "excluding": m.get_string(3).strip_edges()}


## Candidate strings a unit answers to: its keywords and datasheet name, upper
## case (longest first, so multi-word keywords win).
static func _unit_terms(unit: Dictionary) -> Array:
	var meta: Dictionary = unit.get("meta", {})
	var terms: Array = []
	for kw in meta.get("keywords", []):
		var t := str(kw).replace("’", "'").strip_edges().to_upper()
		if t != "" and not t in terms:
			terms.append(t)
	for k in ["name", "datasheet_name"]:
		var n := str(meta.get(k, "")).replace("’", "'").strip_edges().to_upper()
		if n != "" and not n in terms:
			terms.append(n)
	terms.sort_custom(func(a, b): return str(a).length() > str(b).length())
	return terms


## Expand "Infantry/Mounted" style alternatives into concrete phrases.
static func _expand_alternatives(phrase: String) -> Array:
	var out: Array = [""]
	for word in phrase.split(" ", false):
		var alts: PackedStringArray = str(word).split("/", false)
		var nxt: Array = []
		for prefix in out:
			for a in alts:
				nxt.append((str(prefix) + " " + a).strip_edges())
		out = nxt
	return out


## True when every word of `phrase` is consumed by the unit's terms.
static func _phrase_matches(phrase: String, terms: Array) -> bool:
	var rest := phrase.replace("’", "'").strip_edges().to_upper()
	while rest != "":
		var hit := false
		for t in terms:
			var ts := str(t)
			if rest == ts or rest.begins_with(ts + " "):
				rest = rest.substr(ts.length()).strip_edges()
				hit = true
				break
		if not hit:
			return false
	return true


## "" when the unit may bear the enhancement, else the reason.
static func bearer_violation(rec: Dictionary, unit: Dictionary) -> String:
	var r := parse_restriction(rec)
	if r.is_empty():
		return ""
	var terms := _unit_terms(unit)
	var ok := false
	for alt in _expand_alternatives(str(r.phrase)):
		if _phrase_matches(str(alt), terms):
			ok = true
			break
	if not ok:
		return "%s %s only" % [r.phrase, r.scope]
	if str(r.excluding) != "":
		for alt in _expand_alternatives(str(r.excluding)):
			if _phrase_matches(str(alt), terms):
				return "excluding %s units" % r.excluding
	return ""


## "" when `unit` may be given the enhancement `rec` at all (ignoring who else
## holds it), else the reason: the printed restriction always applies; a normal
## enhancement needs a CHARACTER; no enhancement (Upgrades included) on an EPIC
## HERO. An Upgrade is never refused for being on a CHARACTER — the core rule
## lets Upgrades ALSO go on non-CHARACTER units (WP-C46 ruling).
static func bearer_problem(rec: Dictionary, unit: Dictionary, upgrade: bool) -> String:
	if _has_kw(unit, "EPIC HERO"):
		return "EPIC HERO models cannot be given enhancements"
	if not upgrade and not _has_kw(unit, "CHARACTER"):
		return "only CHARACTER units can be given (non-Upgrade) enhancements"
	if not rec.is_empty():
		var why := bearer_violation(rec, unit)
		if why != "":
			return "bearer restriction: %s" % why
	return ""


static func is_upgrade(rec: Dictionary) -> bool:
	return bool(rec.get("upgrade_tag", false))


static func one_per_army(rec: Dictionary) -> bool:
	return str(rec.get("name", "")).to_lower().find("(one per army)") >= 0


static func _has_kw(unit: Dictionary, kw: String) -> bool:
	for k in unit.get("meta", {}).get("keywords", []):
		if str(k).to_upper() == kw:
			return true
	return false


static func _enh_name(enh) -> String:
	if enh is String:
		return enh
	if enh is Dictionary:
		return str(enh.get("name", ""))
	return ""


## Validate every enhancement in `army_data` (units: {id: {meta: {...}}}).
## Returns {"errors": [], "warnings": []} — rule violations are warnings,
## matching the rest of the 11e construction checks (they never block a load).
static func validate_army(army_data: Dictionary) -> Dictionary:
	var out := {"errors": [], "warnings": []}
	var faction = army_data.get("faction", {})
	if not faction is Dictionary:
		return out
	var detachment := str(faction.get("detachment", ""))
	var points_limit := int(faction.get("points", 2000))
	var units = army_data.get("units", {})
	if not units is Dictionary:
		return out
	var choices := {}       # choice key -> count (Upgrade: name; normal: name)
	var holders := {}       # enhancement norm name -> [unit ids]
	for unit_id in units:
		var unit = units[unit_id]
		if not unit is Dictionary:
			continue
		var enh_list = unit.get("meta", {}).get("enhancements", [])
		if not enh_list is Array or enh_list.is_empty():
			continue
		var enh_count := 0
		for enh in enh_list:
			var name := _enh_name(enh)
			if name == "":
				continue
			var rec := find_enhancement(detachment, name)
			var upgrade: bool = is_upgrade(rec) if not rec.is_empty() else (enh is Dictionary and bool(enh.get("upgrade", false)))
			if rec.is_empty() and detachment != "" and not find_detachment(detachment).is_empty() and enhancement_exists(name):
				out.warnings.append("11e: enhancement '%s' on %s is not a %s enhancement" % [name, unit_id, detachment])
			var problem := bearer_problem(rec, unit, upgrade)
			if problem != "":
				out.warnings.append("11e: %senhancement '%s' on %s — %s" % ["Upgrade " if upgrade else "", name, unit_id, problem])
			enh_count += 1
			var key := norm(name)
			if not holders.has(key):
				holders[key] = {"name": name, "units": [], "upgrade": upgrade, "one_per_army": one_per_army(rec) if not rec.is_empty() else false}
			holders[key].units.append(str(unit_id))
		if enh_count > 1:
			out.warnings.append("11e: %s carries %d enhancements (each enhancement goes to a different unit)" % [unit_id, enh_count])
	for key in holders:
		var h: Dictionary = holders[key]
		var n: int = h.units.size()
		if h.upgrade:
			choices[key] = 1
			var cap := 1 if h.one_per_army else 3
			if n > cap:
				out.warnings.append("11e: Upgrade enhancement '%s' on %d units (max %d)" % [h.name, n, cap])
		else:
			choices[key] = n
			if n > 1:
				out.warnings.append("11e: enhancement '%s' taken %d times (once per army): %s" % [h.name, n, ", ".join(h.units)])
	var total := 0
	for key in choices:
		total += int(choices[key])
	var max_enh := int(floor(points_limit / 1000.0)) * 2
	if max_enh > 0 and total > max_enh:
		out.warnings.append("11e: %d enhancement choices exceed the cap of %d at %d pts" % [total, max_enh, points_limit])
	return out
