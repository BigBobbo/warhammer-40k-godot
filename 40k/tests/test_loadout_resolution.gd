extends SceneTree

# MA-LOADOUT: validate per-model ranged-loadout resolution across ALL army files.
#
# For every unit in every res://armies/*.json, drive the REAL
# RE.get_unit_weapons and check:
#   * RESOLVED units (wargear pinned the loadout) report the same number of
#     weapons on every model of a composition role (a weapon's profiles —
#     "Rokkit Launcha – Blasta / – Busta" — count as ONE weapon), and the
#     per-gun totals match the unit's wargear counts.
#   * The change only ever REDUCES over-counting — a unit's total ranged
#     instances never goes UP versus the raw model_profiles menu.
# Plus targeted spot-checks against the printed Codex: Orks kits
# (.llm/codex_11e_wahapedia/orks/wahapedia/Datasheets.csv `loadout`): Boyz,
# Deffkoptas, Beast Snagga Boyz, Kommandos; the Legends Lootas / Burna Boyz
# (D2: unchanged pre-codex rosters).
#
# Usage: godot --headless --path . -s tests/test_loadout_resolution.gd

var passed := 0
var failed := 0
var RE  # RulesEngine autoload (fetched via node — not available as a compile-time identifier under -s)

func _init():
	root.connect("ready", Callable(self, "_run"))
	create_timer(0.2).timeout.connect(_run)

func _check(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL: %s%s" % [label, ("  --  " + detail) if detail != "" else ""])

func _list_army_files() -> Array:
	var out := []
	var d = DirAccess.open("res://armies")
	if d == null:
		return out
	d.list_dir_begin()
	var f = d.get_next()
	while f != "":
		if f.ends_with(".json"):
			out.append("res://armies/%s" % f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

func _load_json(path: String):
	var fa = FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return null
	var txt = fa.get_as_text()
	fa.close()
	return JSON.parse_string(txt)

# Count ranged instances a unit reports WITHOUT resolution (raw menu) — mirrors
# the pre-change _get_model_weapon_ids so we can prove totals only go down.
func _raw_ranged_total(unit: Dictionary) -> int:
	var meta = unit.get("meta", {})
	var mp = meta.get("model_profiles", {})
	var total := 0
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var mt = model.get("model_type", "")
		var use_profile = not mp.is_empty() and mt != "" and mp.has(mt)
		var allowed = mp[mt].get("weapons", []) if use_profile else []
		for w in meta.get("weapons", []):
			if str(w.get("type", "")).to_lower() != "ranged":
				continue
			if use_profile and not (w.get("name", "") in allowed):
				continue
			total += 1
	return total

# Army files kept OUT of the Task C ratchet counts below (every per-unit
# invariant still runs on them). ork11e_codex_test.json is the Codex: Orks (11e)
# stratagem test army built from dataset 1.4.5 datasheets; its Flash Gitz /
# Killa Kans / Tankbustas carry multi-profile guns (Snazzgun, Kan Blasta, Busta
# Rokkit Launcha) that are data-limited over-counters by this test's own
# definition, and counting them would make the legacy-roster ratchet move for
# reasons unrelated to the resolver.
const RATCHET_EXCLUDED_FILES := ["ork11e_codex_test.json"]

# WP-O1b: what a model "carries" is counted in WEAPONS, not profiles. Codex
# weapons often print several profiles (Choppa – Hunter / – Standard, Smash
# Hammer – Hunter / – Standard, Kombi-skorcha – Shoota / – Skorcha); a model
# holding one such weapon reports every profile, which is one weapon.
# `type_filter` "" = the reported entries are weapon NAMES (melee); otherwise
# they are RulesEngine weapon ids of that type (ranged) and are mapped back to
# the datasheet name first.
func _weapon_count(unit: Dictionary, reported: Array, type_filter: String = "") -> int:
	var id_to_name := {}
	if type_filter != "":
		for w in unit.get("meta", {}).get("weapons", []):
			if typeof(w) == TYPE_DICTIONARY and str(w.get("type", "")).to_lower() == type_filter.to_lower():
				id_to_name[RE._generate_weapon_id(str(w.get("name", "")), str(w.get("type", "")))] = str(w.get("name", ""))
	var bases := {}
	for e in reported:
		var n := str(id_to_name.get(str(e), str(e)))
		bases[UnitLoadoutResolver.base_weapon_name(n)] = true
	return bases.size()

# The composition role of each model (index-aligned): its model_type when it
# has one, else the role its POSITION in the datasheet composition forces
# (RulesEngine._positional_roles: 20 Boyz = 2 Nobs + 18 Boyz), else "*" — one
# role for the whole unit. A role's models must carry the same number of
# weapons; different roles may differ (the codex Breaka Boyz Nob has a Choppa
# AND a Smash Hammer, each Breaka Boy only a Smash Hammer).
func _model_roles(unit: Dictionary) -> Array:
	var models = unit.get("models", [])
	var positional = RE._positional_roles(UnitLoadoutResolver.datasheet_key(unit), models.size())
	var out := []
	for i in range(models.size()):
		var mt := str(models[i].get("model_type", ""))
		if mt != "":
			out.append(mt)
		elif positional.size() == models.size():
			out.append(str(positional[i]))
		else:
			out.append("*")
	return out

# {role: [counts]} over the alive models. get_unit_weapons (ranged,
# type_filter "Ranged") keys its dict by model id; get_unit_melee_weapons
# (type_filter "") by "m<index>".
func _counts_by_role(unit: Dictionary, per_model: Dictionary, type_filter: String, grouped: bool) -> Dictionary:
	var roles = _model_roles(unit)
	var models = unit.get("models", [])
	var out := {}
	for i in range(models.size()):
		var m = models[i]
		if not m.get("alive", true):
			continue
		# A model the resolver stamped with NO weapon of this type carries none
		# by its datasheet kit (a Hunting Wolf; a Wolf Guard Terminator whose
		# storm bolter became a storm shield) — WP-S1. Not part of the k count.
		if type_filter != "" and _stamped_empty(m, type_filter):
			continue
		var key := str(m.get("id", "")) if type_filter != "" else "m%d" % i
		var reported = per_model.get(key, [])
		var c := _weapon_count(unit, reported, type_filter) if grouped else int(reported.size())
		var r := str(roles[i])
		var arr: Array = out.get(r, [])
		arr.append(c)
		out[r] = arr
	return out

func _stamped_empty(m: Dictionary, type_filter: String) -> bool:
	var v = m.get(type_filter.to_lower() + "_loadout", null)
	return v is Array and (v as Array).is_empty()

# True when some role's models carry different weapon SETS of this type (each
# took a different wargear option) — then their profile counts may differ.
func _mixed_options_per_role(unit: Dictionary, per_model: Dictionary, type_filter: String) -> bool:
	var id_to_name := {}
	for w in unit.get("meta", {}).get("weapons", []):
		if typeof(w) == TYPE_DICTIONARY and str(w.get("type", "")).to_lower() == type_filter.to_lower():
			id_to_name[RE._generate_weapon_id(str(w.get("name", "")), str(w.get("type", "")))] = str(w.get("name", ""))
	var roles = _model_roles(unit)
	var models = unit.get("models", [])
	var sets_by_role := {}
	for i in range(models.size()):
		if not models[i].get("alive", true):
			continue
		var bases := {}
		for e in per_model.get(str(models[i].get("id", "")), []):
			bases[UnitLoadoutResolver.base_weapon_name(str(id_to_name.get(str(e), str(e))))] = true
		var keys: Array = bases.keys()
		keys.sort()
		var sets: Dictionary = sets_by_role.get(str(roles[i]), {})
		sets[str(keys)] = true
		sets_by_role[str(roles[i])] = sets
	for r in sets_by_role:
		if (sets_by_role[r] as Dictionary).size() > 1:
			return true
	return false

# True when every role's models carry the same count, every count is >= 1 —
# or 0 for a lone model whose roster took no weapon of this type (a codex
# Battlewagon is equipped with only Crushin' Bulk; its big shootas are add-ons).
func _uniform_per_role(unit: Dictionary, by_role: Dictionary, weapon_type: String) -> bool:
	for r in by_role:
		var arr: Array = by_role[r]
		if arr.is_empty():
			continue
		var k := int(arr[0])
		for c in arr:
			if int(c) != k:
				return false
		if k < 1 and not (unit.get("models", []).size() == 1 and not _roster_names_type(unit, weapon_type)):
			return false
	return true

# Does the roster's wargear name any weapon of this type from the datasheet?
func _roster_names_type(unit: Dictionary, weapon_type: String) -> bool:
	var slugs := {}
	for w in unit.get("meta", {}).get("weapons", []):
		if typeof(w) == TYPE_DICTIONARY and str(w.get("type", "")).to_lower() == weapon_type.to_lower():
			slugs[UnitLoadoutResolver.slugify(str(w.get("name", "")))] = true
			slugs[UnitLoadoutResolver.slugify(UnitLoadoutResolver.base_weapon_name(str(w.get("name", ""))))] = true
	for entry in unit.get("meta", {}).get("wargear", []):
		for part in str(entry).split(","):
			var txt := str(part).strip_edges()
			var sp := txt.find(" ")
			if sp > 0 and txt.substr(0, sp).ends_with("x") and txt.substr(0, sp - 1).is_valid_int():
				txt = txt.substr(sp + 1)
			if slugs.has(UnitLoadoutResolver.slugify(txt)):
				return true
	return false

func _fmt_roles(by_role: Dictionary) -> String:
	var parts := []
	for r in by_role:
		parts.append("%s=%s" % [r, str(by_role[r])])
	return ", ".join(PackedStringArray(parts))

func _run():
	if passed > 0 or failed > 0:
		return
	RE = root.get_node_or_null("RulesEngine")
	if RE == null:
		_check("RulesEngine autoload present", false)
		print("=== test_loadout_resolution: %d passed, %d failed ===" % [passed, failed])
		quit(1)
		return
	var resolved_units := 0
	var unresolved_multimodel := []
	var special_units := []  # Task B: units with special-weapon model(s) flagged
	var melee_resolved_units := 0  # Task D: units with resolved melee loadout
	for path in _list_army_files():
		var data = _load_json(path)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var units = data.get("units", {})
		if typeof(units) != TYPE_DICTIONARY:
			continue
		var fname = path.get_file()
		for uid in units:
			var unit = units[uid]
			if typeof(unit) != TYPE_DICTIONARY:
				continue
			var models = unit.get("models", [])
			if models.is_empty():
				continue
			var raw_total = _raw_ranged_total(unit)
			var board = {"units": {uid: unit}}
			var mw = RE.get_unit_weapons(uid, board)  # runs resolution
			# Per-model ranged counts + total after resolution
			var new_total := 0
			var worst := 0
			for mid in mw:
				var c = mw[mid].size()
				new_total += c
				worst = max(worst, c)
			# INVARIANT 1: resolution never ADDS ranged instances.
			_check("no-increase %s/%s" % [fname, uid], new_total <= raw_total,
				"raw=%d new=%d" % [raw_total, new_total])
			# Did this unit get resolved?
			var got_resolved := false
			for m in models:
				if m.has("ranged_loadout"):
					got_resolved = true
					break
			# INVARIANT 4 (revised 2026-07-27): a single-model unit (VEHICLE /
			# MONSTER / character) DOES fire everything it carries — but
			# meta.weapons is the datasheet's option MENU, not its arsenal. A
			# Battlewagon whose roster took a kannon must not be offered the
			# killkannon and zzap gun it never bought, so single-model units are
			# now narrowed from wargear too (see _resolve_single_model_loadout).
			# The pin is therefore "only ever REMOVES, and only menu weapons"
			# rather than "never touched".
			if models.size() < 2:
				_check("single-model-no-increase %s/%s" % [fname, uid],
					new_total <= raw_total, "raw=%d new=%d" % [raw_total, new_total])
				if got_resolved:
					_check("single-model-ranged-subset %s/%s" % [fname, uid],
						_loadout_is_menu_subset(unit, models[0], "Ranged", "ranged_loadout"), "")
			if got_resolved:
				if not fname in RATCHET_EXCLUDED_FILES:
					resolved_units += 1
				# INVARIANT 2 (generalized for Task C; per role + per weapon, WP-O1b):
				# every resolved model of a composition role carries the SAME number
				# k of ranged WEAPONS (k>=1; a weapon's profiles are one weapon). This
				# still catches over-counting but allows legit multi-gun models
				# (Deffkopta: Rokkit Launcha + Slugga, k=2) alongside one-gun mobs, and
				# a role with its own gun (a Warbikers Biker Nob's Dual Kombi-rokkit).
				# A lone model whose roster took no gun may carry none (Battlewagon).
				var k_weapons = _counts_by_role(unit, mw, "Ranged", true)
				_check("resolved-uniform-k %s/%s" % [fname, uid], _uniform_per_role(unit, k_weapons, "Ranged"),
					"weapons per model by role: %s" % _fmt_roles(k_weapons))
				# INVARIANT 3 (generalized): within a role every model reports the
				# same number of weapon PROFILES too (total == k × alive per role),
				# and every alive model reports. Exception (WP-S1, Codex: Space
				# Marines): models of one role that took DIFFERENT options carry
				# the same number of weapons (invariant 2) but not of profiles —
				# a Thunderwolf with a plasma pistol (Standard / Supercharge) next
				# to one with a bolt pistol.
				var k_profiles = _counts_by_role(unit, mw, "Ranged", false)
				var alive := 0
				for m in models:
					if m.get("alive", true) and not _stamped_empty(m, "Ranged"):
						alive += 1
				var reporting := 0
				for r in k_profiles:
					reporting += (k_profiles[r] as Array).size()
				_check("resolved-total==k*alive %s/%s" % [fname, uid],
					reporting == alive and (_uniform_per_role(unit, k_profiles, "Ranged") or
						(_uniform_per_role(unit, k_weapons, "Ranged") and _mixed_options_per_role(unit, mw, "Ranged"))),
					"profiles per model by role: %s (alive=%d)" % [_fmt_roles(k_profiles), alive])
				# INVARIANT 5 (Task C): every stamped gun is one the model_type may
				# actually take — never invent a weapon a model can't have.
				var mp2 = unit.get("meta", {}).get("model_profiles", {})
				var meta_ranged := {}
				for w in unit.get("meta", {}).get("weapons", []):
					if str(w.get("type", "")).to_lower() == "ranged":
						meta_ranged[str(w.get("name", ""))] = true
				for m in models:
					if not m.has("ranged_loadout"):
						continue
					var mt2 = str(m.get("model_type", ""))
					var use_prof = not mp2.is_empty() and mt2 != "" and mp2.has(mt2)
					var allowed2 = mp2[mt2].get("weapons", []) if use_prof else []
					for wname in m["ranged_loadout"]:
						var ok2 = (str(wname) in allowed2) if use_prof else meta_ranged.has(str(wname))
						_check("resolved-gun-allowed %s/%s" % [fname, uid], ok2,
							"'%s' not allowed for model_type '%s'" % [str(wname), mt2])
			elif models.size() >= 2 and worst > 1 and not fname in RATCHET_EXCLUDED_FILES:
				unresolved_multimodel.append("%s/%s(%s)" % [fname, uid, str(unit.get("meta", {}).get("name", ""))])

			# Task B: collect special-weapon models (minority resolved gun). Also
			# assert the marked models are a strict subset of alive models (never
			# mark every model — that would defeat "stands out").
			var special = RE.get_special_weapon_model_ids(unit)
			if special.size() > 0:
				var alive_now := 0
				for m in models:
					if m.get("alive", true):
						alive_now += 1
				_check("special-subset %s/%s" % [fname, uid], special.size() < alive_now,
					"special=%d alive=%d" % [special.size(), alive_now])
				special_units.append("%s/%s(%s): %d special" % [fname, uid, str(unit.get("meta", {}).get("name", "")), special.size()])

			# ---- Task D: melee resolution invariants (mirror of ranged) ----
			var raw_melee = _raw_melee_total(unit)
			var mm = RE.get_unit_melee_weapons(uid, board)  # resolves melee
			var new_melee := 0
			var worst_melee := 0
			for mid in mm:
				var c = mm[mid].size()
				new_melee += c
				worst_melee = max(worst_melee, c)
			# INVARIANT: melee resolution never ADDS melee instances.
			_check("melee-no-increase %s/%s" % [fname, uid], new_melee <= raw_melee,
				"raw=%d new=%d" % [raw_melee, new_melee])
			var got_melee_resolved := false
			for m in models:
				if m.has("melee_loadout"):
					got_melee_resolved = true
					break
			# INVARIANT (revised 2026-07-27, mirrors ranged): a single-model unit's
			# melee list may now be narrowed from wargear too, but only ever by
			# REMOVING weapons that were on the datasheet menu.
			if models.size() < 2:
				_check("single-model-melee-no-increase %s/%s" % [fname, uid],
					new_melee <= raw_melee, "raw=%d new=%d" % [raw_melee, new_melee])
				if got_melee_resolved:
					_check("single-model-melee-subset %s/%s" % [fname, uid],
						_loadout_is_menu_subset(unit, models[0], "Melee", "melee_loadout"), "")
			if got_melee_resolved:
				melee_resolved_units += 1
				# INVARIANT: resolved melee is uniform per composition role — every
				# model of a role carries the same number k>=1 of melee WEAPONS
				# (Choppa – Hunter / – Standard is one Choppa; the codex Breaka Boyz
				# Nob's Choppa + Smash Hammer against a Breaka Boy's Smash Hammer).
				var km = _counts_by_role(unit, mm, "", true)
				_check("melee-uniform-k %s/%s" % [fname, uid], _uniform_per_role(unit, km, "Melee"),
					"melee weapons per model by role: %s" % _fmt_roles(km))

	# -------- Targeted spot-checks --------
	_spot_check_boyz()
	_spot_check_orks_lootas_unchanged()
	_spot_check_burna()
	_spot_check_boyz_incomplete()   # Task C: incomplete-but-consistent (20-Boy mob, 10x Slugga)
	_spot_check_deffkopta()         # Task C: uniform dual-gun (kopta rokkits + slugga)
	_spot_check_special_weapons()   # Task B: minority-gun model detection
	_spot_check_melee()             # Task D: melee loadout resolution

	# Task C: widening coverage must RESOLVE MORE units than the Phase-1 baseline
	# (16) and leave fewer over-counters. Lower/upper bounds so future additions
	# only make this stronger.
	_check("Task C: resolved count increased vs Phase-1 baseline (16)", resolved_units >= 24,
		"resolved=%d (expected >=24)" % resolved_units)
	_check("Task C: unresolved over-counters decreased vs baseline (24)", unresolved_multimodel.size() <= 16,
		"unresolved=%d (expected <=16)" % unresolved_multimodel.size())

	print("")
	print("Resolved units (loadout pinned from wargear): %d" % resolved_units)
	print("Unresolved multi-model over-counters left as-is (data-limited): %d" % unresolved_multimodel.size())
	print("")
	print("Units with special-weapon model(s) flagged (Task B): %d" % special_units.size())
	for u in special_units:
		print("   * %s" % u)
	print("")
	print("Units with resolved MELEE loadout (Task D): %d" % melee_resolved_units)
	for u in unresolved_multimodel:
		print("   - %s" % u)
	print("")
	print("=== test_loadout_resolution: %d passed, %d failed ===" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _weapon_hist(uid: String, unit: Dictionary) -> Dictionary:
	var board = {"units": {uid: unit}}
	var mw = RE.get_unit_weapons(uid, board)
	var hist := {}
	for mid in mw:
		for wid in mw[mid]:
			hist[wid] = int(hist.get(wid, 0)) + 1
	return hist

func _spot_check_boyz():
	var data = _load_json("res://armies/orks.json")
	if typeof(data) != TYPE_DICTIONARY:
		_check("orks.json loads", false); return
	var u = data["units"].get("U_BOYZ_K", {})
	var hist = _weapon_hist("U_BOYZ_K", u)
	# Codex: Orks Boyz (Datasheets.csv loadout): "Every Nob is equipped with: 1
	# Kustom Choppa; 1 Kombi-skorcha. Every Boy is equipped with: 1 Choppa; 1
	# Shoota; 1 Slugga." 10 Boyz = 1 Nob + 9 Boyz (wargear "1x Kombi-skorcha,
	# 9x Shoota, 9x Slugga, ..."). The pre-codex check ("10x Slugga" -> 10
	# Sluggas, no Shoota) described the 10e mob, whose Boss Nob had a slugga too.
	_check("Boyz -> 9 Slugga (every Boy; the codex Nob has none)", hist.get("slugga_ranged", 0) == 9, str(hist))
	_check("Boyz -> 9 Shoota (every Boy)", hist.get("shoota_ranged", 0) == 9, str(hist))
	_check("Boyz -> 1 Kombi-skorcha, both profiles (the Nob)",
		hist.get("kombi_skorcha___shoota_ranged", 0) == 1 and hist.get("kombi_skorcha___skorcha_ranged", 0) == 1, str(hist))
	_check("Boyz -> no Big shoota", not hist.has("big_shoota_ranged"), str(hist))
	_check("Boyz -> no Rokkit", not hist.has("rokkit_launcha___busta_ranged") and not hist.has("rokkit_launcha___blasta_ranged"), str(hist))

func _spot_check_orks_lootas_unchanged():
	# orks.json Lootas is ALREADY resolved via model_type -> must be untouched.
	var data = _load_json("res://armies/orks.json")
	var u = data["units"].get("U_LOOTAS_A", {})
	var hist = _weapon_hist("U_LOOTAS_A", u)
	_check("orks Lootas -> 8 Deffgun (model_type resolved, unchanged)", hist.get("deffgun_ranged", 0) == 8, str(hist))
	_check("orks Lootas -> 3 KMB (unchanged)", hist.get("kustom_mega_blasta_ranged", 0) == 3, str(hist))
	_check("orks Lootas -> no Big shoota", not hist.has("big_shoota_ranged"), str(hist))

func _spot_check_burna():
	var data = _load_json("res://armies/battlewagons.json")
	if typeof(data) != TYPE_DICTIONARY:
		return
	var u = data["units"].get("U_BURNA_BOYZ_A", {})
	if u.is_empty():
		return
	var hist = _weapon_hist("U_BURNA_BOYZ_A", u)
	# wargear = 4x Burna + 1x Big shoota
	_check("Burna Boyz -> 4 Burna", hist.get("burna_ranged", 0) == 4, str(hist))
	_check("Burna Boyz -> 1 Big shoota", hist.get("big_shoota_ranged", 0) == 1, str(hist))

func _spot_check_boyz_incomplete():
	# The 20-model mobs. Pre-codex this was Task C CASE C (wargear recorded
	# only "9x Slugga, 1x Slugga" -> every model a Slugga). Codex: Orks Boyz
	# are "1-2 Nob, 9-18 Boy" sold as 10 or 20, so 20 Boyz = 2 Nobs (Kustom
	# Choppa + Kombi-skorcha) + 18 Boyz (Choppa + Shoota + Slugga). The army
	# files used to record a 20-model mob's kit as 1 Nob + 19 Boyz, which handed
	# the 2nd Nob a Boy's Choppa; generate-armies re-splits it (WP-O1b).
	var data = _load_json("res://armies/orks.json")
	if typeof(data) != TYPE_DICTIONARY:
		return
	for uid in ["U_BOYZ_E", "U_BOYZ_F"]:
		var u = data["units"].get(uid, {})
		if u.is_empty():
			continue
		var n = u.get("models", []).size()
		_check("Boyz %s is a 20-model mob" % uid, n == 20, "models=%d" % n)
		var hist = _weapon_hist(uid, u)
		_check("Boyz %s -> 18 Slugga + 18 Shoota (the Boyz)" % uid,
			hist.get("slugga_ranged", 0) == 18 and hist.get("shoota_ranged", 0) == 18, str(hist))
		_check("Boyz %s -> 2 Kombi-skorcha (the 2 Nobs)" % uid,
			hist.get("kombi_skorcha___shoota_ranged", 0) == 2 and hist.get("kombi_skorcha___skorcha_ranged", 0) == 2, str(hist))
		_check("Boyz %s -> no Big shoota" % uid, not hist.has("big_shoota_ranged"), str(hist))
		_check("Boyz %s -> no Rokkit" % uid, not hist.has("rokkit_launcha___busta_ranged"), str(hist))
		var mh = _melee_hist(uid, u)
		_check("Boyz %s melee -> 2 Kustom Choppa (both Nobs) + 18 Choppa" % uid,
			mh.get("Kustom Choppa", 0) == 2 and mh.get("Choppa", 0) == 18, str(mh))

func _spot_check_deffkopta():
	# Task C CASE B: every Deffkopta carries two guns. Codex: Orks: "Every model
	# is equipped with: 1 Choppa; 1 Rokkit Launcha; 1 Slugga; 1 Spinnin' Blades"
	# (the pre-codex "Kopta rokkits" are gone). The Rokkit Launcha prints two
	# profiles (Blasta / Busta) and the roster names it once — "3x Rokkit
	# Launcha, 3x Slugga" over 3 models -> a uniform 2-gun set (it used to drop
	# the launcha and stamp Slugga only: WP-O1b, RulesEngine resolver v3).
	var data = _load_json("res://armies/battlewagons.json")
	if typeof(data) != TYPE_DICTIONARY:
		return
	var u = data["units"].get("U_DEFFKOPTAS_A", {})
	if u.is_empty():
		return
	var n = u.get("models", []).size()
	var hist = _weapon_hist("U_DEFFKOPTAS_A", u)
	_check("Deffkoptas -> %d Rokkit Launcha (both profiles)" % n,
		hist.get("rokkit_launcha___blasta_ranged", 0) == n and hist.get("rokkit_launcha___busta_ranged", 0) == n, str(hist))
	_check("Deffkoptas -> %d Slugga" % n, hist.get("slugga_ranged", 0) == n, str(hist))
	# Each model is stamped resolved with a 2-gun set (not left as the raw menu).
	var m0 = u.get("models", [])[0]
	_check("Deffkoptas -> model stamped 2-gun set (Rokkit Launcha + Slugga)",
		_weapon_count(u, m0.get("ranged_loadout", [])) == 2 and "Slugga" in m0.get("ranged_loadout", []),
		str(m0.get("ranged_loadout", [])))
	var mh = _melee_hist("U_DEFFKOPTAS_A", u)
	_check("Deffkoptas melee -> %d Choppa + %d Spinnin' Blades" % [n, n],
		mh.get("Choppa", 0) == n and mh.get("Spinnin' blades", 0) == n, str(mh))
	# Task B: a uniform 2-gun mob has no stand-out model.
	_check("Deffkoptas -> 0 special (uniform)", RE.get_special_weapon_model_ids(u).size() == 0, str(RE.get_special_weapon_model_ids(u)))

func _spot_check_special_weapons():
	# Task B: minority-gun model detection (the special/heavy-weapon models).
	# Burna Boyz (battlewagons): 4 Burna + 1 Big shoota -> exactly 1 special.
	var bw = _load_json("res://armies/battlewagons.json")
	if typeof(bw) == TYPE_DICTIONARY:
		var u = bw["units"].get("U_BURNA_BOYZ_A", {})
		if not u.is_empty():
			var sp = RE.get_special_weapon_model_ids(u)
			_check("Burna Boyz -> 1 special-weapon model", sp.size() == 1, "special=%s" % str(sp))
	var ork = _load_json("res://armies/orks.json")
	if typeof(ork) == TYPE_DICTIONARY:
		# orks Lootas: 8 Deffgun + 3 KMB (model_type resolved) -> 3 special (KMB minority).
		var lu = ork["units"].get("U_LOOTAS_A", {})
		if not lu.is_empty():
			var sp2 = RE.get_special_weapon_model_ids(lu)
			_check("orks Lootas -> 3 special (KMB minority)", sp2.size() == 3, "special=%s" % str(sp2))
		# Codex Boyz: the Nob carries a Kombi-skorcha, every Boy a Shoota + Slugga,
		# so the Nob(s) stand out (pre-codex every model had the same Slugga and
		# none did). Boyz K: 1 Nob -> 1 special (model 0); Boyz E (20): 2 Nobs.
		var bk = ork["units"].get("U_BOYZ_K", {})
		if not bk.is_empty():
			var spk = RE.get_special_weapon_model_ids(bk)
			_check("Boyz K -> 1 special (the Nob's Kombi-skorcha)", spk == [str(bk["models"][0].get("id", ""))], str(spk))
		var be = ork["units"].get("U_BOYZ_E", {})
		if not be.is_empty():
			var spe = RE.get_special_weapon_model_ids(be)
			spe.sort()
			var nobs = [str(be["models"][0].get("id", "")), str(be["models"][1].get("id", ""))]
			nobs.sort()
			_check("Boyz E -> 2 special (the 2 Nobs' Kombi-skorchas)", spe == nobs, str(spe))
	# Single-model units never get a special marker (guarded on models.size()).
	var sm = _load_json("res://armies/space_marines.json")
	if typeof(sm) == TYPE_DICTIONARY:
		for uid in sm.get("units", {}):
			var su = sm["units"][uid]
			if typeof(su) == TYPE_DICTIONARY and su.get("models", []).size() == 1:
				_check("single-model %s -> 0 special" % uid, RE.get_special_weapon_model_ids(su).size() == 0, "")
				break

# Count melee instances a unit reports WITHOUT resolution (menu-based), mirroring
# the pre-change get_unit_melee_weapons so we can prove melee totals only go down.
# Single-model narrowing may only pick weapons that were already on the unit's
# datasheet menu for that type — it must never invent a profile.
func _loadout_is_menu_subset(unit: Dictionary, model: Dictionary, weapon_type: String, loadout_key: String) -> bool:
	var menu := {}
	for w in unit.get("meta", {}).get("weapons", []):
		if str(w.get("type", "")).to_lower() == weapon_type.to_lower():
			menu[str(w.get("name", ""))] = true
	var resolved = model.get(loadout_key, [])
	if typeof(resolved) != TYPE_ARRAY:
		return false
	for n in resolved:
		if not menu.has(str(n)):
			return false
	return true


func _raw_melee_total(unit: Dictionary) -> int:
	var meta = unit.get("meta", {})
	var mp = meta.get("model_profiles", {})
	var all_melee := []
	for w in meta.get("weapons", []):
		if str(w.get("type", "")).to_lower() == "melee":
			var wn = w.get("name", "")
			if wn not in all_melee:
				all_melee.append(wn)
	var total := 0
	for model in unit.get("models", []):
		if not model.get("alive", true):
			continue
		var mt = model.get("model_type", "")
		if not mp.is_empty() and mt != "" and mp.has(mt):
			var allowed = mp[mt].get("weapons", [])
			for wn in all_melee:
				if wn in allowed:
					total += 1
		else:
			total += all_melee.size()
	return total

func _melee_hist(uid: String, unit: Dictionary) -> Dictionary:
	var board = {"units": {uid: unit}}
	var mm = RE.get_unit_melee_weapons(uid, board)
	var hist := {}
	for mid in mm:
		for wn in mm[mid]:
			hist[str(wn)] = int(hist.get(str(wn), 0)) + 1
	return hist

func _spot_check_melee():
	# Task D: melee loadout resolution (mirror of the ranged spot-checks).
	# Beast Snagga Boyz (Orks_2000): wargear 9x Choppa + 1x Power snappa over 10
	# models -> 9 Choppa + 1 Power Snappa, dropping the Close combat weapon ghost.
	# Codex: Orks: "Every Nob is equipped with: 1 Power Snappa; 1 Slugga. Every
	# Beast Snagga Boy is equipped with: 1 Choppa; 1 Slugga." The codex Choppa
	# prints two profiles (Hunter / Standard): a Boy reports both, one weapon.
	var o = _load_json("res://armies/Orks_2000.json")
	if typeof(o) == TYPE_DICTIONARY:
		var bs = o["units"].get("U_BEAST_SNAGGA_BOYZ_A", {})
		if not bs.is_empty():
			var mmh = _melee_hist("U_BEAST_SNAGGA_BOYZ_A", bs)
			_check("Beast Snagga melee -> 9 Choppa (Hunter + Standard profiles)",
				mmh.get("Choppa – Hunter", 0) == 9 and mmh.get("Choppa – Standard", 0) == 9, str(mmh))
			_check("Beast Snagga melee -> 1 Power Snappa (the Nob)", mmh.get("Power Snappa", 0) == 1, str(mmh))
			_check("Beast Snagga melee -> no Close combat weapon", not mmh.has("Close combat weapon"), str(mmh))
		# Kommandos: Codex: Orks "Every model is equipped with: 1 Choppa; 1 Slugga"
		# — the Nob included. Pre-codex the Boss Nob's profile only allowed a Big
		# choppa, so a roster of "10x Choppa" was SAFELY declined (never invent a
		# weapon a model can't take). Under the codex the Nob carries a Choppa,
		# so resolving every model to a Choppa is now correct.
		var k = o["units"].get("U_KOMMANDOS_A", {})
		if not k.is_empty():
			var board_k = {"units": {"U_KOMMANDOS_A": k}}
			var km = RE.get_unit_melee_weapons("U_KOMMANDOS_A", board_k)
			var stamped := 0
			for m in k.get("models", []):
				if m.has("melee_loadout"):
					stamped += 1
			var choppas := 0
			for mid in km:
				if _weapon_count(k, km[mid]) == 1 and UnitLoadoutResolver.slugify(UnitLoadoutResolver.base_weapon_name(str(km[mid][0]))).begins_with("choppa"):
					choppas += 1
			_check("Kommandos melee -> resolved: every model (the Nob too) a Choppa",
				stamped == k.get("models", []).size() and choppas == k.get("models", []).size(),
				"stamped=%d choppas=%d of %d: %s" % [stamped, choppas, k.get("models", []).size(), str(km)])
	# Burna Boyz (battlewagons): 4x Cuttin' flames + 1x Close combat weapon.
	var bw = _load_json("res://armies/battlewagons.json")
	if typeof(bw) == TYPE_DICTIONARY:
		var b = bw["units"].get("U_BURNA_BOYZ_A", {})
		if not b.is_empty():
			var mmh2 = _melee_hist("U_BURNA_BOYZ_A", b)
			_check("Burna melee -> 4 Cuttin' flames", mmh2.get("Cuttin' flames", 0) == 4, str(mmh2))
			_check("Burna melee -> 1 Close combat weapon", mmh2.get("Close combat weapon", 0) == 1, str(mmh2))
	# Boyz melee. Pre-codex this was CASE D (the roster said nothing about melee,
	# so the 10e default kit — Boss Nob big choppa, Boy choppa — pinned it). The
	# codex roster lists the melee kit ("1x Kustom Choppa, 9x Choppa"), and the
	# codex datasheet ("Every Nob is equipped with: 1 Kustom Choppa; 1
	# Kombi-skorcha. Every Boy is equipped with: 1 Choppa; ...") agrees: 9
	# Choppa + 1 Kustom Choppa — never the menu's Big Choppa / Power Klaw
	# options, which the roster did not take.
	var ork = _load_json("res://armies/orks.json")
	if typeof(ork) == TYPE_DICTIONARY:
		var bk = ork["units"].get("U_BOYZ_K", {})
		if not bk.is_empty():
			var mmh3 = _melee_hist("U_BOYZ_K", bk)
			_check("Boyz K melee -> 9 Choppa (every Boy)", mmh3.get("Choppa", 0) == 9, str(mmh3))
			_check("Boyz K melee -> 1 Kustom Choppa (the codex Nob)", mmh3.get("Kustom Choppa", 0) == 1, str(mmh3))
			_check("Boyz K melee -> no Big Choppa / Power Klaw (options not taken)",
				not mmh3.has("Big Choppa") and not mmh3.has("Power Klaw"), str(mmh3))
			_check("Boyz K melee -> no Close combat weapon ghost", not mmh3.has("Close combat weapon"), str(mmh3))
			var per_model_one := true
			for m in bk.get("models", []):
				if m.get("melee_loadout", []).size() != 1:
					per_model_one = false
					break
			_check("Boyz K melee -> exactly one melee weapon per model", per_model_one, "")
		_spot_check_positional_roles(ork)


# CASE D fallback: units imported before model_profiles existed (and older saves)
# carry no model_type at all, so the role has to come from the model's POSITION
# in the datasheet's unit composition (codex: "1-2 Nob", then "9-18 Boy").
# Verified on a real Boyz mob with model_profiles AND its wargear lines
# stripped, so only the codex default kit (Nob: Kustom Choppa) can pin it.
func _spot_check_positional_roles(ork) -> void:
	if typeof(ork) != TYPE_DICTIONARY:
		return
	var src = ork["units"].get("U_BOYZ_K", {})
	if src.is_empty():
		return

	var unit = src.duplicate(true)
	unit["id"] = "U_BOYZ_NOPROFILES"
	unit["meta"]["model_profiles"] = {}
	unit["meta"]["wargear"] = []  # nothing but the composition position to go on
	unit.erase("_loadout_checked")
	unit.erase("_loadout_version")
	for m in unit.get("models", []):
		m.erase("model_type")
		m.erase("ranged_loadout")
		m.erase("melee_loadout")

	var mm = RE.get_unit_melee_weapons("U_BOYZ_NOPROFILES", {"units": {"U_BOYZ_NOPROFILES": unit}})
	var hist := {}
	for mid in mm:
		for wn in mm[mid]:
			hist[str(wn)] = int(hist.get(str(wn), 0)) + 1
	_check("no-model_profiles Boyz -> 9 Choppa via composition order", hist.get("Choppa", 0) == 9, str(hist))
	_check("no-model_profiles Boyz -> 1 Kustom Choppa (model 0 is the Nob)", hist.get("Kustom Choppa", 0) == 1, str(hist))
	_check("no-model_profiles Boyz -> no Power Klaw ghost", not hist.has("Power Klaw"), str(hist))
	var m0_melee = unit["models"][0].get("melee_loadout", [])
	_check("no-model_profiles Boyz -> model 0 is the Nob", m0_melee == ["Kustom Choppa"], str(m0_melee))

	# Ambiguity guard: two open-ended composition roles (Lootas are 1-2 Spanners
	# + 4-8 Lootas) cannot be split by position, so nothing is stamped.
	var lootas = ork["units"].get("U_LOOTAS_A", {})
	if not lootas.is_empty():
		var la = lootas.duplicate(true)
		la["id"] = "U_LOOTAS_NOPROFILES"
		la["meta"]["model_profiles"] = {}
		la["meta"]["wargear"] = []
		la.erase("_loadout_checked")
		la.erase("_loadout_version")
		for m in la.get("models", []):
			m.erase("model_type")
			m.erase("ranged_loadout")
			m.erase("melee_loadout")
		RE.get_unit_melee_weapons("U_LOOTAS_NOPROFILES", {"units": {"U_LOOTAS_NOPROFILES": la}})
		var any_stamp := false
		for m in la.get("models", []):
			if m.has("melee_loadout"):
				any_stamp = true
				break
		_check("two open-ended composition roles -> left unresolved (never guess)", not any_stamp, "")
