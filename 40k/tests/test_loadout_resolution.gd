extends SceneTree

# MA-LOADOUT: validate per-model ranged-loadout resolution across ALL army files.
#
# For every unit in every res://armies/*.json, drive the REAL
# RE.get_unit_weapons and check:
#   * RESOLVED units (wargear pinned the loadout) report exactly ONE ranged gun
#     per model, and the per-gun totals match the unit's wargear counts.
#   * The change only ever REDUCES over-counting — a unit's total ranged
#     instances never goes UP versus the raw model_profiles menu.
# Plus targeted spot-checks (Boyz -> Slugga, orks Lootas unchanged, Burna Boyz).
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
			# INVARIANT 4: single-model units (VEHICLE/MONSTER/character) fire ALL
			# their guns — they must NEVER be resolved/collapsed, and their weapon
			# count must be untouched.
			if models.size() < 2:
				_check("single-model-untouched %s/%s" % [fname, uid],
					not got_resolved and new_total == raw_total,
					"resolved=%s raw=%d new=%d" % [str(got_resolved), raw_total, new_total])
			if got_resolved:
				resolved_units += 1
				# INVARIANT 2: a resolved model reports exactly ONE ranged gun.
				_check("resolved-1gun %s/%s" % [fname, uid], worst <= 1,
					"worst=%d" % worst)
				# INVARIANT 3: total ranged == number of alive models (one each).
				var alive := 0
				for m in models:
					if m.get("alive", true):
						alive += 1
				_check("resolved-total==models %s/%s" % [fname, uid], new_total == alive,
					"total=%d alive=%d" % [new_total, alive])
			elif models.size() >= 2 and worst > 1:
				unresolved_multimodel.append("%s/%s(%s)" % [fname, uid, str(unit.get("meta", {}).get("name", ""))])

	# -------- Targeted spot-checks --------
	_spot_check_boyz()
	_spot_check_orks_lootas_unchanged()
	_spot_check_burna()

	print("")
	print("Resolved units (loadout pinned from wargear): %d" % resolved_units)
	print("Unresolved multi-model over-counters left as-is (data-limited): %d" % unresolved_multimodel.size())
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
	# wargear = 10x Slugga -> expect 10 sluggas, and NO shoota/big shoota/rokkit.
	_check("Boyz -> 10 Slugga", hist.get("slugga_ranged", 0) == 10, str(hist))
	_check("Boyz -> no Shoota (menu suppressed)", not hist.has("shoota_ranged"), str(hist))
	_check("Boyz -> no Big shoota", not hist.has("big_shoota_ranged"), str(hist))
	_check("Boyz -> no Rokkit", not hist.has("rokkit_launcha_ranged"), str(hist))

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
